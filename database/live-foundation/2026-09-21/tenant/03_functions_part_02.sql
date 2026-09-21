-- Edusentia tenant foundation: public functions
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

SET check_function_bodies=off;

CREATE OR REPLACE FUNCTION public.finance_portal_report_detail(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; h jsonb; rrole text:=public.current_app_role()::text;
begin
 if rrole not in ('student','parent_guardian') then raise exception 'Student or guardian access required' using errcode='42501'; end if;
 select e.student_id into sid from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.id=target_report_id and r.status='published' and r.deleted_at is null;
 if sid is null then raise exception 'Published report was not found'; end if;
 if rrole='student' and not exists(select 1 from public.students where id=sid and profile_id=auth.uid() and deleted_at is null) then raise exception 'Access denied' using errcode='42501'; end if;
 if rrole='parent_guardian' and not exists(select 1 from public.guardian_links where student_id=sid and auth_user_id=auth.uid() and can_view_reports) then raise exception 'Access denied' using errcode='42501'; end if;
 h:=public.finance_student_hold_status(sid); if coalesce((h->>'block_grade_details')::boolean,false) then return jsonb_build_object('locked',true,'hold',h,'report_id',target_report_id); end if;
 return jsonb_build_object('locked',false,'hold',h,
  'report',(select jsonb_build_object('id',r.id,'report_number',r.report_number,'status',r.status,'published_at',r.published_at,'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'class_name',c.name,'term_name',t.name,'academic_year_name',y.name,'teacher_comment',r.teacher_comment,'head_comment',r.head_comment,'attendance_present',r.attendance_present,'attendance_total',r.attendance_total,'position',public.report_position(r.id)) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id where r.id=target_report_id),
  'subjects',coalesce((select jsonb_agg(jsonb_build_object('subject_id',sub.id,'subject',sub.name,'total_score',sr.total_score,'grade',sr.grade,'remark',sr.remark,'grade_point',sr.grade_point,'teacher_initials',sr.teacher_initials) order by sub.display_order,sub.name) from public.subject_results sr join public.subjects sub on sub.id=sr.subject_id where sr.report_id=target_report_id),'[]'::jsonb),
  'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=target_report_id),0)
 );
end $function$

CREATE OR REPLACE FUNCTION public.finance_post_adjustment(target_student_id uuid, target_account_id uuid, adjustment_type text, amount_value numeric, notes_text text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare txid uuid; debit numeric:=0; credit numeric:=0;
begin perform public.finance_require_access('finance_fees',true); perform public.finance_require_capability('fee_adjust'); if adjustment_type not in ('waiver','discount','refund','adjustment_debit','adjustment_credit') then raise exception 'Adjustment type is invalid'; end if; if amount_value<=0 or btrim(coalesce(notes_text,''))='' then raise exception 'A positive amount and reason are required'; end if; if not exists(select 1 from public.finance_fee_accounts where id=target_account_id and student_id=target_student_id) then raise exception 'Student fee account was not found'; end if; if adjustment_type in ('refund','adjustment_debit') then debit:=amount_value; else credit:=amount_value; end if; insert into public.finance_fee_transactions(student_id,entry_type,debit_amount,credit_amount,transaction_date,notes,created_by) values(target_student_id,adjustment_type,debit,credit,current_date,btrim(notes_text),auth.uid()) returning id into txid; insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(txid,target_account_id,amount_value); insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'finance_fee_transactions',txid,'FEE_ADJUSTMENT_POSTED',jsonb_build_object('type',adjustment_type,'amount',amount_value,'account_id',target_account_id),notes_text); return txid; end $function$

CREATE OR REPLACE FUNCTION public.finance_protect_final_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='DELETE' then raise exception 'Payroll rows cannot be deleted; use a corrective run.' using errcode='42501'; end if;
  if old.payment_status='paid' and (new.* is distinct from old.*) then raise exception 'Paid payroll items are locked; use a corrective run.' using errcode='42501'; end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.finance_protect_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='DELETE' then
    raise exception 'Issued invoices cannot be deleted. Use a ledger adjustment or reversal.' using errcode='42501';
  end if;
  if new.id is distinct from old.id
     or new.account_id is distinct from old.account_id
     or new.invoice_no is distinct from old.invoice_no
     or new.student_id is distinct from old.student_id
     or new.academic_year_id is distinct from old.academic_year_id
     or new.term_id is distinct from old.term_id
     or new.class_id is distinct from old.class_id
     or new.issued_at is distinct from old.issued_at then
    raise exception 'Invoice identity is immutable.' using errcode='42501';
  end if;
  if new.* is distinct from old.* and exists(
    select 1 from public.finance_fee_allocations a where a.account_id=old.account_id
  ) then
    raise exception 'An invoice with posted ledger activity is locked. Use an adjustment instead.' using errcode='42501';
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.finance_record_payment(target_student_id uuid, target_account_id uuid, amount_value numeric, payment_method_text text, payment_reference_text text DEFAULT ''::text, payment_date_value date DEFAULT CURRENT_DATE, notes_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tx public.finance_fee_transactions%rowtype; acc record; selected record; remaining numeric:=amount_value; alloc numeric; receipt text; allocated numeric:=0;
begin
 perform public.finance_require_access('finance_fees',true); perform public.finance_require_capability('fee_collect');
 if amount_value is null or amount_value<=0 then raise exception 'Payment amount must be greater than zero'; end if;
 if payment_method_text not in ('cash','bank_transfer','mobile_money','cheque','card','other') then raise exception 'Select a valid payment method'; end if;
 select b.*,y.start_date,t.sequence into selected from public.finance_fee_account_balances b join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id where b.id=target_account_id and b.student_id=target_student_id;
 if selected.id is null then raise exception 'Student fee account was not found'; end if;
 perform pg_advisory_xact_lock(hashtextextended('finance_student_'||target_student_id::text,0)); receipt:=public.finance_generate_receipt_no();
 insert into public.finance_fee_transactions(student_id,entry_type,credit_amount,payment_method,payment_reference,receipt_no,transaction_date,notes,created_by) values(target_student_id,'payment',amount_value,payment_method_text,btrim(coalesce(payment_reference_text,'')),receipt,coalesce(payment_date_value,current_date),btrim(coalesce(notes_text,'')),auth.uid()) returning * into tx;
 for acc in select b.*,y.start_date,t.sequence from public.finance_fee_account_balances b join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id where b.student_id=target_student_id and (y.start_date<selected.start_date or (y.start_date=selected.start_date and t.sequence<=selected.sequence)) and b.balance>0 order by y.start_date,t.sequence,b.created_at loop exit when remaining<=0; alloc:=least(remaining,acc.balance); insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(tx.id,acc.id,alloc); remaining:=remaining-alloc; allocated:=allocated+alloc; end loop;
 if remaining>0 then insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(tx.id,target_account_id,remaining) on conflict(transaction_id,account_id) do update set amount=public.finance_fee_allocations.amount+excluded.amount; allocated:=allocated+remaining; end if;
 insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'finance_fee_transactions',tx.id,'FEE_PAYMENT_POSTED',jsonb_build_object('student_id',target_student_id,'amount',amount_value,'receipt_no',receipt,'method',payment_method_text),'Fee payment posted');
 return jsonb_build_object('transaction_id',tx.id,'receipt_no',receipt,'amount',amount_value,'allocated',allocated,'statement',public.finance_student_statement(target_student_id));
end $function$

CREATE OR REPLACE FUNCTION public.finance_require_access(feature_code text, require_write boolean DEFAULT false, allowed_roles text[] DEFAULT ARRAY['accountant'::text, 'system_admin'::text])
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text:=public.current_app_role()::text;
  l jsonb;
begin
  if auth.uid() is null or r is null or not (r=any(allowed_roles)) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not public.finance_feature_enabled(feature_code) then
    raise exception 'This finance feature is not enabled by the current licence plan' using errcode='42501';
  end if;
  if r='accountant' and not exists(
    select 1 from public.accounts_office_staff a
    where a.profile_id=auth.uid() and a.active and a.deleted_at is null
  ) then
    raise exception 'Accountant directory record is not active' using errcode='42501';
  end if;

  if r in ('accountant','system_admin') then
    perform public.require_sensitive_access();
    if public.current_aal()<>'aal2' then
      raise exception 'Multi-factor authentication is required for Finance access' using errcode='42501';
    end if;
  end if;

  if r='accountant' then
    if feature_code in ('finance_fees','finance_statements') and not public.finance_staff_capability('finance_read') then
      raise exception 'Your Accounts Office permission does not allow Finance access' using errcode='42501';
    elsif feature_code='financial_holds' and not public.finance_staff_capability('financial_hold') then
      raise exception 'Your Accounts Office permission does not allow financial holds' using errcode='42501';
    elsif feature_code='payroll' and not public.finance_staff_capability('payroll') then
      raise exception 'Your Accounts Office permission does not allow payroll access' using errcode='42501';
    end if;
  end if;

  l:=public.license_snapshot_for_role(r);
  if coalesce((l->>'read_allowed')::boolean,false)<>true then
    raise exception 'Platform licence access is restricted' using errcode='42501';
  end if;
  if require_write and coalesce((l->>'write_allowed')::boolean,false)<>true then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;
  return r;
end
$function$

CREATE OR REPLACE FUNCTION public.finance_require_capability(capability text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin if not public.finance_staff_capability(capability) then raise exception 'Your Accounts Office permission does not allow this action' using errcode='42501'; end if; end $function$

CREATE OR REPLACE FUNCTION public.finance_require_payroll_access(require_write boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin perform public.finance_require_access('payroll',require_write); perform public.finance_require_capability('payroll'); end $function$

CREATE OR REPLACE FUNCTION public.finance_reverse_payment(target_transaction_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare original public.finance_fee_transactions%rowtype; rev public.finance_fee_transactions%rowtype; a record;
begin perform public.finance_require_access('finance_fees',true); perform public.finance_require_capability('fee_adjust'); if btrim(coalesce(reason_text,''))='' then raise exception 'A reversal reason is required'; end if; select * into original from public.finance_fee_transactions where id=target_transaction_id and entry_type='payment'; if original.id is null then raise exception 'Posted payment was not found'; end if; if exists(select 1 from public.finance_fee_transactions where reversal_of_id=original.id) then raise exception 'This payment has already been reversed'; end if; insert into public.finance_fee_transactions(student_id,entry_type,debit_amount,payment_method,payment_reference,reversal_of_id,transaction_date,notes,created_by) values(original.student_id,'payment_reversal',original.credit_amount,original.payment_method,original.payment_reference,original.id,current_date,btrim(reason_text),auth.uid()) returning * into rev; for a in select account_id,amount from public.finance_fee_allocations where transaction_id=original.id loop insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(rev.id,a.account_id,a.amount); end loop; insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason) values(auth.uid(),'finance_fee_transactions',original.id,'FEE_PAYMENT_REVERSED',to_jsonb(original),to_jsonb(rev),reason_text); return jsonb_build_object('reversal_id',rev.id,'reversed_transaction_id',original.id,'statement',public.finance_student_statement(original.student_id)); end $function$

CREATE OR REPLACE FUNCTION public.finance_save_accounts_staff(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); r public.accounts_office_staff%rowtype; staffno text; actor_role text;
begin
 actor_role:=public.finance_require_access('finance_fees',true,array['system_admin']);
 if btrim(coalesce(payload->>'full_name',''))='' then raise exception 'Full name is required'; end if;
 if rid is null then staffno:=public.finance_generate_staff_no();
   insert into public.accounts_office_staff(staff_no,full_name,phone,email,contact_address,job_title,finance_role,active,created_by)
   values(staffno,btrim(payload->>'full_name'),btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),''),btrim(coalesce(payload->>'contact_address','')),coalesce(nullif(btrim(payload->>'job_title'),''),'Accounts Office Staff'),coalesce(nullif(payload->>'finance_role',''),'accounts_officer'),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else
   update public.accounts_office_staff set full_name=btrim(payload->>'full_name'),phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),''),contact_address=btrim(coalesce(payload->>'contact_address','')),job_title=coalesce(nullif(btrim(payload->>'job_title'),''),job_title),finance_role=coalesce(nullif(payload->>'finance_role',''),finance_role),active=coalesce((payload->>'active')::boolean,active) where id=rid and deleted_at is null returning * into r;
   if r.id is null then raise exception 'Accounts Office staff record was not found'; end if;
 end if;
 return to_jsonb(r);
end $function$

CREATE OR REPLACE FUNCTION public.finance_save_fee_schedule(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
 rid uuid:=public.safe_uuid(payload->>'id');
 y uuid:=public.safe_uuid(payload->>'academic_year_id');
 tm uuid:=public.safe_uuid(payload->>'term_id');
 c uuid:=public.safe_uuid(payload->>'class_id');
 g uuid:=public.safe_uuid(payload->>'fee_group_id');
 amt numeric:=coalesce((payload->>'amount')::numeric,-1);
 due_date_value date:=public.safe_date(payload->>'due_date');
 description_value text:=coalesce(nullif(btrim(payload->>'description'),''),'Term fee');
 active_value boolean:=coalesce((payload->>'active')::boolean,true);
 r public.finance_fee_schedules%rowtype;
 class_record record;
 existing_allocations int;
 synced int:=0;
 synced_one int:=0;
 configured_count int:=0;
begin
 perform public.finance_require_access('finance_fees',true);
 perform public.finance_require_capability('fee_config');
 if y is null or tm is null or amt<0 or (g is null and c is null) then
   raise exception 'Academic year, term, fee group/class and valid fee amount are required';
 end if;
 if not exists(select 1 from public.terms t where t.id=tm and t.academic_year_id=y and t.deleted_at is null) then
   raise exception 'The selected term does not belong to the academic year';
 end if;

 if g is not null then
   if not exists(select 1 from public.finance_fee_groups x where x.id=g and x.active) then
     raise exception 'The selected fee group is unavailable';
   end if;
   if not exists(
     select 1 from public.finance_fee_group_classes m
     join public.classes x on x.id=m.class_id
     where m.fee_group_id=g and x.active and x.deleted_at is null
   ) then raise exception 'The selected fee group has no active classes'; end if;

   for class_record in
     select x.id as class_id,x.name
     from public.finance_fee_group_classes m
     join public.classes x on x.id=m.class_id
     where m.fee_group_id=g and x.active and x.deleted_at is null
     order by m.sort_order,x.level_order,x.name
   loop
     select count(*) into existing_allocations
     from public.finance_fee_accounts a
     join public.finance_fee_allocations al on al.account_id=a.id
     where a.academic_year_id=y and a.term_id=tm and a.class_id=class_record.class_id;
     if existing_allocations>0 and exists(
       select 1 from public.finance_fee_schedules x
       where x.academic_year_id=y and x.term_id=tm and x.class_id=class_record.class_id and x.amount<>amt
     ) then
       raise exception 'The fee for % already has posted transactions. Keep the original fee and use an adjustment instead.',class_record.name;
     end if;
   end loop;

   for class_record in
     select x.id as class_id
     from public.finance_fee_group_classes m
     join public.classes x on x.id=m.class_id
     where m.fee_group_id=g and x.active and x.deleted_at is null
     order by m.sort_order,x.level_order,x.name
   loop
     insert into public.finance_fee_schedules(academic_year_id,term_id,class_id,fee_group_id,amount,due_date,description,active,created_by)
     values(y,tm,class_record.class_id,g,amt,due_date_value,description_value,active_value,auth.uid())
     on conflict(academic_year_id,term_id,class_id) do update
       set fee_group_id=excluded.fee_group_id,
           amount=excluded.amount,
           due_date=excluded.due_date,
           description=excluded.description,
           active=excluded.active,
           updated_at=now()
     returning * into r;
     configured_count:=configured_count+1;
     if r.active then
       synced_one:=public.finance_sync_fee_accounts(r.id);
       synced:=synced+synced_one;
     end if;
   end loop;

   return jsonb_build_object(
     'fee_group_id',g,
     'classes_configured',configured_count,
     'accounts_synchronized',synced,
     'academic_year_id',y,
     'term_id',tm,
     'amount',amt,
     'due_date',due_date_value,
     'description',description_value,
     'active',active_value
   );
 end if;

 if not exists(select 1 from public.classes x where x.id=c and x.deleted_at is null and x.active) then
   raise exception 'The selected class is unavailable';
 end if;
 select count(*) into existing_allocations
 from public.finance_fee_accounts a
 join public.finance_fee_allocations al on al.account_id=a.id
 where a.academic_year_id=y and a.term_id=tm and a.class_id=c;
 if existing_allocations>0 and exists(
   select 1 from public.finance_fee_schedules x
   where x.academic_year_id=y and x.term_id=tm and x.class_id=c and x.amount<>amt
 ) then
   raise exception 'This fee already has posted transactions. Keep the original fee and use an adjustment instead.';
 end if;
 insert into public.finance_fee_schedules(academic_year_id,term_id,class_id,fee_group_id,amount,due_date,description,active,created_by)
 values(y,tm,c,null,amt,due_date_value,description_value,active_value,auth.uid())
 on conflict(academic_year_id,term_id,class_id) do update
   set fee_group_id=null,amount=excluded.amount,due_date=excluded.due_date,description=excluded.description,active=excluded.active,updated_at=now()
 returning * into r;
 if r.active then synced:=public.finance_sync_fee_accounts(r.id); end if;
 return to_jsonb(r)||jsonb_build_object('accounts_synchronized',synced);
end $function$

CREATE OR REPLACE FUNCTION public.finance_save_hold_policy(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare r public.finance_hold_policy%rowtype; begin perform public.finance_require_access('financial_holds',true); perform public.finance_require_capability('financial_hold'); update public.finance_hold_policy set enabled=coalesce((payload->>'enabled')::boolean,enabled),minimum_outstanding=coalesce((payload->>'minimum_outstanding')::numeric,minimum_outstanding),grace_days=coalesce((payload->>'grace_days')::int,grace_days),block_grade_details=coalesce((payload->>'block_grade_details')::boolean,block_grade_details),block_report_pdf=coalesce((payload->>'block_report_pdf')::boolean,block_report_pdf),block_transcript=coalesce((payload->>'block_transcript')::boolean,block_transcript),block_certificate=coalesce((payload->>'block_certificate')::boolean,block_certificate),updated_by=auth.uid() where id=1 returning * into r; return to_jsonb(r); end $function$

CREATE OR REPLACE FUNCTION public.finance_save_payroll_profile(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); teacherid uuid:=public.safe_uuid(payload->>'teacher_id'); gradeid uuid:=public.safe_uuid(payload->>'salary_grade_id'); payrollno text; r public.finance_payroll_profiles%rowtype; override_amt numeric;
begin
 perform public.finance_require_access('payroll',true);
 if teacherid is null or not exists(select 1 from public.teachers where id=teacherid and deleted_at is null and active) then raise exception 'Select an active teacher'; end if;
 if gradeid is not null and not exists(select 1 from public.finance_salary_grades where id=gradeid and active) then raise exception 'Salary grade is unavailable'; end if;
 override_amt:=case when nullif(payload->>'basic_salary_override','') is null then null else (payload->>'basic_salary_override')::numeric end;
 if override_amt is not null and override_amt<0 then raise exception 'Salary override cannot be negative'; end if;
 if rid is null then payrollno:=coalesce(nullif(btrim(payload->>'payroll_number'),''),public.finance_generate_payroll_number());
   insert into public.finance_payroll_profiles(teacher_id,salary_grade_id,payroll_number,basic_salary_override,ssnit_number,tax_id,active,created_by)
   values(teacherid,gradeid,payrollno,override_amt,btrim(coalesce(payload->>'ssnit_number','')),btrim(coalesce(payload->>'tax_id','')),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else update public.finance_payroll_profiles set salary_grade_id=gradeid,payroll_number=coalesce(nullif(btrim(payload->>'payroll_number'),''),payroll_number),basic_salary_override=override_amt,ssnit_number=btrim(coalesce(payload->>'ssnit_number','')),tax_id=btrim(coalesce(payload->>'tax_id','')),active=coalesce((payload->>'active')::boolean,active) where id=rid and teacher_id=teacherid returning * into r; end if;
 if r.id is null then raise exception 'Payroll profile was not found'; end if; return to_jsonb(r);
end $function$

CREATE OR REPLACE FUNCTION public.finance_save_payroll_rule(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); r public.finance_payroll_rules%rowtype; typ text:=btrim(coalesce(payload->>'rule_type','')); eff date:=public.safe_date(payload->>'effective_from'); endd date:=public.safe_date(payload->>'effective_to'); ratev numeric; fixedv numeric;
begin
 perform public.finance_require_access('payroll_statutory',true);
 if typ not in ('ssnit_employee','ssnit_employer','tax','allowance','deduction') or btrim(coalesce(payload->>'rule_code',''))='' or btrim(coalesce(payload->>'name',''))='' or eff is null then raise exception 'Rule code, type, name and effective date are required'; end if;
 ratev:=case when nullif(payload->>'rate','') is null then null else (payload->>'rate')::numeric end; fixedv:=case when nullif(payload->>'fixed_amount','') is null then null else (payload->>'fixed_amount')::numeric end;
 if coalesce(ratev,0)<0 or coalesce(fixedv,0)<0 or (endd is not null and endd<eff) then raise exception 'Payroll rule values are invalid'; end if;
 if rid is null then insert into public.finance_payroll_rules(rule_code,rule_type,name,rate,fixed_amount,rule_json,effective_from,effective_to,active,created_by) values(btrim(payload->>'rule_code'),typ,btrim(payload->>'name'),ratev,fixedv,coalesce(payload->'rule_json','{}'::jsonb),eff,endd,coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else update public.finance_payroll_rules set rule_code=btrim(payload->>'rule_code'),rule_type=typ,name=btrim(payload->>'name'),rate=ratev,fixed_amount=fixedv,rule_json=coalesce(payload->'rule_json',rule_json),effective_from=eff,effective_to=endd,active=coalesce((payload->>'active')::boolean,active) where id=rid returning * into r; end if;
 return to_jsonb(r);
end $function$

CREATE OR REPLACE FUNCTION public.finance_save_salary_grade(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); r public.finance_salary_grades%rowtype; amt numeric:=coalesce((payload->>'basic_salary')::numeric,-1);
begin
 perform public.finance_require_access('payroll',true);
 if btrim(coalesce(payload->>'code',''))='' or btrim(coalesce(payload->>'name',''))='' or amt<0 then raise exception 'Grade code, name and a valid basic salary are required'; end if;
 if rid is null then insert into public.finance_salary_grades(code,name,basic_salary,active,created_by) values(btrim(payload->>'code'),btrim(payload->>'name'),amt,coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else update public.finance_salary_grades set code=btrim(payload->>'code'),name=btrim(payload->>'name'),basic_salary=amt,active=coalesce((payload->>'active')::boolean,active) where id=rid returning * into r; end if;
 return to_jsonb(r);
end $function$

CREATE OR REPLACE FUNCTION public.finance_save_teacher_loan(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); tid uuid:=public.safe_uuid(payload->>'teacher_id'); r public.finance_teacher_loans%rowtype; principal numeric:=coalesce((payload->>'principal_amount')::numeric,0); monthly numeric:=coalesce((payload->>'monthly_deduction')::numeric,0); ref text;
begin
 perform public.finance_require_access('payroll',true);
 if tid is null or principal<=0 or monthly<=0 or public.safe_date(payload->>'start_date') is null then raise exception 'Teacher, principal, monthly deduction and start date are required'; end if;
 if rid is null then ref:=coalesce(nullif(btrim(payload->>'reference_no'),''),'LOAN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
   insert into public.finance_teacher_loans(teacher_id,reference_no,principal_amount,monthly_deduction,start_date,status,notes,created_by) values(tid,ref,principal,monthly,public.safe_date(payload->>'start_date'),coalesce(nullif(payload->>'status',''),'active'),btrim(coalesce(payload->>'notes','')),auth.uid()) returning * into r;
 else if exists(select 1 from public.finance_payroll_item_lines l join public.finance_payroll_items i on i.id=l.payroll_item_id where l.loan_id=rid and i.payment_status='paid') and exists(select 1 from public.finance_teacher_loans x where x.id=rid and (x.principal_amount<>principal or x.monthly_deduction<>monthly)) then raise exception 'A loan with paid deductions cannot have its financial terms changed'; end if;
   update public.finance_teacher_loans set principal_amount=principal,monthly_deduction=monthly,start_date=public.safe_date(payload->>'start_date'),status=coalesce(nullif(payload->>'status',''),status),notes=btrim(coalesce(payload->>'notes','')) where id=rid and teacher_id=tid returning * into r; end if;
 return to_jsonb(r)||jsonb_build_object('remaining_balance',public.finance_loan_balance(r.id));
end $function$

CREATE OR REPLACE FUNCTION public.finance_session_capabilities()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r text:=public.current_app_role()::text;
begin
  if r not in ('accountant','system_admin') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.finance_require_access('finance_fees',false,array['accountant','system_admin']);
  return jsonb_build_object(
    'finance_read',public.finance_staff_capability('finance_read'),
    'fee_collect',public.finance_staff_capability('fee_collect'),
    'fee_config',public.finance_staff_capability('fee_config'),
    'fee_adjust',public.finance_staff_capability('fee_adjust'),
    'financial_hold',public.finance_feature_enabled('financial_holds') and public.finance_staff_capability('financial_hold'),
    'payroll',public.finance_feature_enabled('payroll') and public.finance_staff_capability('payroll'),
    'manage_finance_staff',(r='system_admin')
  );
end
$function$

CREATE OR REPLACE FUNCTION public.finance_set_hold_override(target_student_id uuid, mode_text text, reason_text text, ends_at_value timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare r public.finance_hold_overrides%rowtype; begin perform public.finance_require_access('financial_holds',true); perform public.finance_require_capability('financial_hold'); if mode_text not in ('force_lock','force_unlock') or btrim(coalesce(reason_text,''))='' then raise exception 'Lock/unlock action and reason are required'; end if; update public.finance_hold_overrides set active=false,updated_at=now() where student_id=target_student_id and active; insert into public.finance_hold_overrides(student_id,mode,reason,ends_at,created_by) values(target_student_id,mode_text,btrim(reason_text),ends_at_value,auth.uid()) returning * into r; return public.finance_student_hold_status(target_student_id)||jsonb_build_object('override_id',r.id); end $function$

CREATE OR REPLACE FUNCTION public.finance_staff_capability(capability text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text:=public.current_app_role()::text;
  fr text;
begin
  if r='system_admin' then return true; end if;
  if r<>'accountant' then return false; end if;
  select a.finance_role into fr
  from public.accounts_office_staff a
  where a.profile_id=auth.uid() and a.active and a.deleted_at is null
  order by a.updated_at desc limit 1;
  if fr is null then return false; end if;
  return case fr
    when 'cashier' then capability in ('finance_read','fee_collect')
    when 'accounts_officer' then capability in ('finance_read','fee_collect')
    when 'accountant' then capability in ('finance_read','fee_collect','fee_config','fee_adjust','financial_hold','payroll')
    when 'payroll_officer' then capability in ('finance_read','payroll')
    when 'finance_manager' then capability in ('finance_read','fee_collect','fee_config','fee_adjust','financial_hold','payroll')
    else false
  end;
end
$function$

CREATE OR REPLACE FUNCTION public.finance_student_hold_status(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare p public.finance_hold_policy%rowtype; o public.finance_hold_overrides%rowtype; overdue numeric:=0; total_due numeric:=0; automatic boolean:=false; locked boolean:=false; reason text:='';
begin
  total_due:=public.finance_student_outstanding(target_student_id);
  select * into p from public.finance_hold_policy where id=1;
  if not public.finance_feature_enabled('financial_holds') then
    return jsonb_build_object('locked',false,'automatic',false,'outstanding',total_due,'reason','','block_grade_details',false,'block_report_pdf',false,'block_transcript',false,'block_certificate',false);
  end if;
  select coalesce(sum(greatest(b.balance,0)),0) into overdue
  from public.finance_fee_account_balances b
  where b.student_id=target_student_id and greatest(b.balance,0)>0
    and coalesce(b.due_date,current_date)+(coalesce(p.grace_days,0)||' days')::interval<now();
  automatic:=coalesce(p.enabled,false) and overdue>coalesce(p.minimum_outstanding,0);
  select * into o from public.finance_hold_overrides x where x.student_id=target_student_id and x.active and x.starts_at<=now() and (x.ends_at is null or x.ends_at>now()) order by x.created_at desc limit 1;
  if o.id is not null then locked:=o.mode='force_lock'; reason:=o.reason;
  else locked:=automatic; if automatic then reason:='Outstanding school fees require financial clearance.'; end if; end if;
  return jsonb_build_object('locked',locked,'automatic',automatic,'outstanding',total_due,'overdue',overdue,'reason',reason,
    'block_grade_details',locked and coalesce(p.block_grade_details,true),'block_report_pdf',locked and coalesce(p.block_report_pdf,true),
    'block_transcript',locked and coalesce(p.block_transcript,false),'block_certificate',locked and coalesce(p.block_certificate,false));
end $function$

CREATE OR REPLACE FUNCTION public.finance_student_outstanding(target_student_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce(sum(greatest(balance,0)),0)::numeric from public.finance_fee_account_balances where student_id=target_student_id
$function$

CREATE OR REPLACE FUNCTION public.finance_student_statement(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r text:=public.current_app_role()::text; allowed boolean:=false;
begin
  if r in ('accountant','system_admin') then
    perform public.finance_require_access('finance_statements',false,array['accountant','system_admin']); allowed:=true;
  elsif r='parent_guardian' then
    allowed:=exists(select 1 from public.guardian_links where auth_user_id=auth.uid() and student_id=target_student_id);
  elsif r='student' then
    allowed:=exists(select 1 from public.students where id=target_student_id and profile_id=auth.uid() and deleted_at is null);
  end if;
  if not allowed then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'school',coalesce((select jsonb_build_object('school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,'logo_url',logo_url,'tenant_code',tenant_code,'report_footer',report_footer) from public.school_settings limit 1),'{}'::jsonb),
    'student',(select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)) from public.students s where s.id=target_student_id),
    'outstanding',public.finance_student_outstanding(target_student_id),
    'hold',public.finance_student_hold_status(target_student_id),
    'accounts',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,
      'invoice_id',i.id,'invoice_no',i.invoice_no,'invoice_issued_at',i.issued_at,'invoice_amount',i.issued_amount,'invoice_description',i.description,
      'academic_year_id',b.academic_year_id,'academic_year_name',y.name,
      'term_id',b.term_id,'term_name',t.name,'class_id',b.class_id,'class_name',c.name,
      'term_fee',b.term_fee_amount,'due_date',b.due_date,'paid',b.amount_paid,'balance',b.balance,'status',b.status,'balance_remaining',b.balance_remaining
    ) order by y.start_date,t.sequence)
    from public.finance_fee_account_balances b
    join public.academic_years y on y.id=b.academic_year_id
    join public.terms t on t.id=b.term_id
    join public.classes c on c.id=b.class_id
    left join public.finance_fee_invoices i on i.account_id=b.id
    where b.student_id=target_student_id),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'receipt_no',x.receipt_no,'amount',x.credit_amount,'method',x.payment_method,'reference',x.payment_reference,'transaction_date',x.transaction_date,'notes',x.notes,'reversed',exists(select 1 from public.finance_fee_transactions r2 where r2.reversal_of_id=x.id)) order by x.transaction_date desc,x.created_at desc) from public.finance_fee_transactions x where x.student_id=target_student_id and x.entry_type='payment'),'[]'::jsonb)
  );
end
$function$

CREATE OR REPLACE FUNCTION public.finance_sync_enrollment_fee_accounts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s record;
begin
  if new.active and new.deleted_at is null then
    for s in select * from public.finance_fee_schedules where academic_year_id=new.academic_year_id and class_id=new.class_id and active loop
      insert into public.finance_fee_accounts(student_id,enrollment_id,academic_year_id,term_id,class_id,schedule_id,term_fee_amount)
      values(new.student_id,new.id,new.academic_year_id,s.term_id,new.class_id,s.id,s.amount)
      on conflict(student_id,term_id) do nothing;
    end loop;
  end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.finance_sync_fee_accounts(target_schedule_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s public.finance_fee_schedules%rowtype; affected_count int:=0;
begin
 select * into s from public.finance_fee_schedules where id=target_schedule_id and active;
 if s.id is null then raise exception 'Fee schedule was not found'; end if;

 insert into public.finance_fee_accounts(student_id,enrollment_id,academic_year_id,term_id,class_id,schedule_id,term_fee_amount)
 select e.student_id,e.id,e.academic_year_id,s.term_id,e.class_id,s.id,s.amount
 from public.enrollments e
 join public.students st on st.id=e.student_id
 where e.academic_year_id=s.academic_year_id
   and e.class_id=s.class_id
   and e.active and e.deleted_at is null
   and st.deleted_at is null and st.status='active'
 on conflict(student_id,term_id) do update
 set enrollment_id=excluded.enrollment_id,
     academic_year_id=excluded.academic_year_id,
     class_id=excluded.class_id,
     schedule_id=excluded.schedule_id,
     term_fee_amount=excluded.term_fee_amount
 where not exists(
   select 1 from public.finance_fee_allocations al
   where al.account_id=finance_fee_accounts.id
 );
 get diagnostics affected_count=row_count;
 return affected_count;
end $function$

CREATE OR REPLACE FUNCTION public.finance_sync_hr_staff_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if new.teacher_id is not null then select id into new.hr_staff_member_id from public.hr_staff_members where source_type='teacher' and source_id=new.teacher_id; end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.finance_sync_invoice_from_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  inv_id uuid;
  due_value date;
  description_value text;
  schedule_value uuid;
begin
  select s.id,s.due_date,coalesce(nullif(btrim(s.description),''),'Term fee')
  into schedule_value,due_value,description_value
  from public.finance_fee_schedules s
  where s.id=new.schedule_id;

  description_value:=coalesce(description_value,'Term fee');
  select i.id into inv_id from public.finance_fee_invoices i where i.account_id=new.id;

  if inv_id is null then
    insert into public.finance_fee_invoices(
      account_id,invoice_no,student_id,academic_year_id,term_id,class_id,schedule_id,
      issued_amount,due_date,description,issued_at,created_by
    ) values(
      new.id,public.finance_generate_invoice_no(),new.student_id,new.academic_year_id,new.term_id,new.class_id,
      schedule_value,new.term_fee_amount,due_value,description_value,coalesce(new.created_at,now()),auth.uid()
    );
  else
    update public.finance_fee_invoices
    set schedule_id=schedule_value,
        issued_amount=new.term_fee_amount,
        due_date=due_value,
        description=description_value
    where id=inv_id
      and (schedule_id,issued_amount,due_date,description)
          is distinct from (schedule_value,new.term_fee_amount,due_value,description_value);
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.finance_teacher_salary_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid;
begin
 if public.current_app_role() not in ('class_teacher','subject_teacher') then raise exception 'Teacher access required' using errcode='42501'; end if;
 if not public.finance_feature_enabled('payroll') then return jsonb_build_object('teacher',null,'payments','[]'::jsonb); end if;
 select id into tid from public.teachers where profile_id=auth.uid() and active and deleted_at is null order by updated_at desc limit 1;
 if tid is null then return jsonb_build_object('teacher',null,'payments','[]'::jsonb); end if;
 return jsonb_build_object('teacher',(select jsonb_build_object('id',t.id,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no,'payroll_number',p.payroll_number) from public.teachers t left join public.finance_payroll_profiles p on p.teacher_id=t.id where t.id=tid),
 'payments',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('year',r.payroll_year,'month',r.payroll_month,'pay_date',r.pay_date,'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.line_type,l.description) from public.finance_payroll_item_lines l where l.payroll_item_id=i.id),'[]'::jsonb)) order by r.payroll_year desc,r.payroll_month desc) from public.finance_payroll_items i join public.finance_payroll_runs r on r.id=i.run_id where i.teacher_id=tid and i.payment_status='paid'),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.freeze_report_grading_guide()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_guide jsonb;
begin
  if new.status='submitted' and old.status is distinct from new.status then
    perform public.recalculate_report_grades(new.id);
    v_guide:=public.resolve_report_grading_guide(new.id);
    new.grading_scale_snapshot:=v_guide;
    new.grading_scale_scope:=coalesce(v_guide->'scope','{}'::jsonb);
    new.grading_scale_frozen_at:=now();
  end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
  base_name text:=lower(regexp_replace(coalesce(requested_base,''),'[^a-z0-9]','','g'));
  email_domain text:=public.canonical_school_email_domain();
  candidate text;
  suffix integer:=1;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles p
    where p.id=actor_id
      and p.active
      and public.current_app_role_for(p.role)='system_admin'
  ) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if auth.uid() is not null and auth.uid()<>actor_id then
    raise exception 'Access denied' using errcode='42501';
  end if;

  base_name:=left(coalesce(nullif(base_name,''),'user'),40);
  perform pg_advisory_xact_lock(
    hashtextextended('school_user_email_'||email_domain||'_'||base_name,0)
  );
  candidate:=base_name||'@'||email_domain;

  while exists(
    select 1 from auth.users u
    where lower(coalesce(u.email,''))=lower(candidate)
      and (target_user_id is null or u.id<>target_user_id)
  ) loop
    suffix:=suffix+1;
    if suffix>99999 then
      raise exception 'A unique school user email address could not be generated';
    end if;
    candidate:=left(base_name,greatest(1,40-length(suffix::text)))||
      suffix::text||'@'||email_domain;
  end loop;
  return candidate;
end
$function$

CREATE OR REPLACE FUNCTION public.generate_report_number(target_report_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare prefix text; yname text; seq bigint;
begin
  select coalesce(report_number_prefix,'SCH') into prefix from public.school_settings limit 1;
  select regexp_replace(ay.name::text,'[^0-9A-Za-z]','','g')
  into yname from public.student_reports r join public.terms t on t.id=r.term_id
  join public.academic_years ay on ay.id=t.academic_year_id where r.id=target_report_id;
  select count(*)+1 into seq from public.student_reports where report_number is not null;
  return upper(prefix)||'-'||coalesce(nullif(yname,''),to_char(current_date,'YYYY'))||'-'||lpad(seq::text,6,'0');
end $function$

CREATE OR REPLACE FUNCTION public.generate_school_identifier(identifier_kind text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  kind text:=lower(btrim(coalesce(identifier_kind,'')));
  root text;
  serial_number bigint;
  candidate text;
begin
  if auth.uid() is null or not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  if kind not in ('student','teacher','principal','headteacher') then
    raise exception 'Identifier type is invalid' using errcode='22023';
  end if;

  select upper(btrim(s.identifier_root)) into root
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;

  if coalesce(root,'') !~ '^[A-Z]{3}[0-9]{6}$' then
    raise exception 'The school identifier root is not configured correctly';
  end if;

  if kind='student' then
    loop
      serial_number:=nextval('public.student_identifier_seq');
      if serial_number>999999 then raise exception 'The student identifier sequence is exhausted'; end if;
      candidate:=root||'-STU-'||lpad(serial_number::text,6,'0');
      exit when not exists(select 1 from public.students s where lower(s.admission_no::text)=lower(candidate));
    end loop;
  else
    loop
      serial_number:=nextval('public.staff_identifier_seq');
      if serial_number>999999 then raise exception 'The staff identifier sequence is exhausted'; end if;
      candidate:=root||'-STF-'||lpad(serial_number::text,6,'0');
      exit when not exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(candidate))
        and not exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(candidate));
    end loop;
  end if;

  return candidate;
end
$function$

CREATE OR REPLACE FUNCTION public.generate_staff_id_card_number(target_academic_year_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare prefix text;year_code text;candidate text;seq bigint;attempt integer:=0;
begin select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'RCE'),'[^0-9A-Za-z]','','g')) into prefix from public.school_settings limit 1;select regexp_replace(name::text,'[^0-9A-Za-z]','','g') into year_code from public.academic_years where id=target_academic_year_id and deleted_at is null;if year_code is null then raise exception 'Academic year not found';end if;loop attempt:=attempt+1;if attempt>1000 then raise exception 'Unable to allocate a unique staff ID card number';end if;seq:=nextval('public.staff_id_card_number_seq');candidate:=coalesce(nullif(prefix,''),'RCE')||'-STAFF-'||year_code||'-'||lpad(seq::text,6,'0');exit when not exists(select 1 from public.staff_id_cards where card_number=candidate);end loop;return candidate;end$function$

CREATE OR REPLACE FUNCTION public.generate_student_id_card_number(target_academic_year_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare prefix text;year_code text;candidate text;seq bigint;attempt integer:=0; begin select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'RCE'),'[^0-9A-Za-z]','','g')) into prefix from public.school_settings limit 1; select regexp_replace(name::text,'[^0-9A-Za-z]','','g') into year_code from public.academic_years where id=target_academic_year_id and deleted_at is null; if year_code is null then raise exception 'Academic year not found';end if;year_code:=coalesce(nullif(year_code,''),upper(substr(replace(target_academic_year_id::text,'-',''),1,8))); loop attempt:=attempt+1;if attempt>1000 then raise exception 'Unable to allocate a unique ID card number';end if; seq:=nextval('public.student_id_card_number_seq');candidate:=coalesce(nullif(prefix,''),'RCE')||'-ID-'||year_code||'-'||lpad(seq::text,6,'0'); exit when not exists(select 1 from public.student_id_cards where card_number=candidate); end loop; return candidate; end$function$

CREATE OR REPLACE FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleaned text:=upper(regexp_replace(btrim(coalesce(subject_name,'')),'[^[:alnum:] ]+',' ','g'));
  meaningful text[];
  all_words text[];
  selected_words text[];
  token text;
  prefix text:='';
  candidate text;
  attempt integer:=0;
begin
  if auth.uid() is null or not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(cleaned)='' then raise exception 'Subject name is required'; end if;
  select coalesce(array_agg(word order by ord),'{}'::text[]) into all_words
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'';
  select coalesce(array_agg(word order by ord),'{}'::text[]) into meaningful
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'' and word not in ('AND','OF','THE','FOR','IN','TO');
  selected_words:=case when cardinality(meaningful)>0 then meaningful else all_words end;
  if cardinality(selected_words)=1 then
    prefix:=left(regexp_replace(selected_words[1],'[^A-Z0-9]','','g'),3);
  else
    foreach token in array selected_words loop
      prefix:=prefix||left(token,1);
      exit when length(prefix)>=4;
    end loop;
  end if;
  if prefix='' then prefix:='SUB'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nis_subject_code_'||prefix,0));
  loop
    attempt:=attempt+1;
    candidate:=prefix||lpad(floor(random()*10000)::integer::text,4,'0');
    if not exists(
      select 1 from public.subjects s
      where lower(s.code::text)=lower(candidate)
        and (exclude_subject_id is null or s.id<>exclude_subject_id)
    ) then return candidate; end if;
    if attempt>=250 then raise exception 'A unique subject code could not be generated'; end if;
  end loop;
end $function$

CREATE OR REPLACE FUNCTION public.get_academic_calendar_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  y_id uuid := null;
  y_name text := null;
  y_start_date date := null;
  y_end_date date := null;

  t_id uuid := null;
  t_name text := null;
  t_sequence smallint := null;
  t_start_date date := null;
  t_end_date date := null;

  n_term_id uuid := null;
  n_term_name text := null;
  n_term_sequence smallint := null;
  n_term_start_date date := null;
  n_term_end_date date := null;
  n_academic_year_id uuid := null;
  n_academic_year_name text := null;
  n_academic_year_start_date date := null;
  n_academic_year_end_date date := null;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  select ay.id, ay.name::text, ay.start_date, ay.end_date
  into y_id, y_name, y_start_date, y_end_date
  from public.academic_years ay
  where ay.deleted_at is null
    and ay.start_date is not null
    and ay.start_date <= current_date
    and (ay.end_date is null or ay.end_date >= current_date)
  order by ay.start_date desc, ay.created_at desc
  limit 1;

  if y_id is not null then
    select tm.id, tm.name::text, tm.sequence, tm.start_date, tm.end_date
    into t_id, t_name, t_sequence, t_start_date, t_end_date
    from public.terms tm
    where tm.deleted_at is null
      and tm.academic_year_id = y_id
      and tm.start_date is not null
      and tm.start_date <= current_date
      and (tm.end_date is null or tm.end_date >= current_date)
    order by tm.start_date desc, tm.sequence desc
    limit 1;
  end if;

  select tm.id,
         tm.name::text,
         tm.sequence,
         tm.start_date,
         tm.end_date,
         ay.id,
         ay.name::text,
         ay.start_date,
         ay.end_date
  into n_term_id,
       n_term_name,
       n_term_sequence,
       n_term_start_date,
       n_term_end_date,
       n_academic_year_id,
       n_academic_year_name,
       n_academic_year_start_date,
       n_academic_year_end_date
  from public.terms tm
  join public.academic_years ay
    on ay.id = tm.academic_year_id
   and ay.deleted_at is null
  where tm.deleted_at is null
    and tm.start_date is not null
    and tm.start_date > current_date
  order by tm.start_date asc, tm.sequence asc
  limit 1;

  return jsonb_build_object(
    'today', current_date,
    'active', y_id is not null,
    'academic_year', case when y_id is null then null else jsonb_build_object(
      'id', y_id,
      'name', y_name,
      'start_date', y_start_date,
      'end_date', y_end_date
    ) end,
    'term', case when t_id is null then null else jsonb_build_object(
      'id', t_id,
      'name', t_name,
      'sequence', t_sequence,
      'start_date', t_start_date,
      'end_date', t_end_date
    ) end,
    'next_period', case when n_term_id is null then null else jsonb_build_object(
      'academic_year_id', n_academic_year_id,
      'academic_year_name', n_academic_year_name,
      'academic_year_start_date', n_academic_year_start_date,
      'academic_year_end_date', n_academic_year_end_date,
      'term_id', n_term_id,
      'term_name', n_term_name,
      'term_sequence', n_term_sequence,
      'term_start_date', n_term_start_date,
      'term_end_date', n_term_end_date
    ) end
  );
end
$function$

CREATE OR REPLACE FUNCTION public.get_academic_configuration()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'academic_years',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc nulls last) from public.academic_years x where x.deleted_at is null),'[]'::jsonb),
    'terms',coalesce((select jsonb_agg(to_jsonb(x) order by x.academic_year_id,x.sequence) from public.terms x where x.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(to_jsonb(x) order by x.level_order,x.name) from public.classes x where x.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.name) from public.subjects x where x.deleted_at is null),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(jsonb_build_object(
      'id',cs.id,'class_id',cs.class_id,'class_name',c.name,'subject_id',cs.subject_id,'subject_name',s.name,
      'teacher_id',cs.teacher_id,'teacher_name',p.full_name,'active',cs.active
    ) order by c.level_order,c.name,s.display_order,s.name)
      from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id
      left join public.profiles p on p.id=cs.teacher_id),'[]'::jsonb),
    'grading_scales',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.min_mark desc) from public.grading_scales x where x.deleted_at is null),'[]'::jsonb),
    'assessment_schemes',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'academic_year_id',s.academic_year_id,'term_id',s.term_id,
      'class_id',s.class_id,'subject_id',s.subject_id,'active',s.active,
      'components',coalesce((select jsonb_agg(to_jsonb(c) order by c.display_order,c.name)
        from public.assessment_components c where c.scheme_id=s.id),'[]'::jsonb),
      'total_weight',(select coalesce(sum(c.weight),0) from public.assessment_components c where c.scheme_id=s.id)
    ) order by lower(s.name)) from public.assessment_schemes s where s.deleted_at is null),'[]'::jsonb),
    'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role))
      order by lower(p.full_name),p.id) from public.profiles p where p.active),'[]'::jsonb),
    'teacher_records',coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,
      'profile_id',t.profile_id,
      'staff_no',t.staff_no,
      'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
      'label',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
        ||' • '||t.staff_no::text
        ||case when t.profile_id is null then ' • No linked account' else '' end,
      'active',t.active
    ) order by lower(concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)),t.staff_no::text)
      from public.teachers t
      where t.deleted_at is null and t.active and t.employment_status='active'),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_bootstrap_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare p jsonb; v_current_role text; current_year uuid; v_license jsonb; v_write_allowed boolean:=false; v_read_allowed boolean:=false; v_has_emergency boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_current_role:=public.current_app_role()::text;
  if v_current_role is null or v_current_role not in ('platform_super_admin','system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student') then raise exception 'Active supported profile not found' using errcode='42501'; end if;
  v_license:=public.license_snapshot_for_role(v_current_role); v_write_allowed:=coalesce((v_license->>'write_allowed')::boolean,false); v_read_allowed:=coalesce((v_license->>'read_allowed')::boolean,false);
  if v_current_role in ('system_admin','class_teacher','subject_teacher') then v_has_emergency:=public.has_any_active_emergency_delegation(auth.uid()); end if;
  if v_current_role<>'platform_super_admin' and not v_read_allowed then insert into public.license_verification_logs(license_id,actor_id,actor_role,computed_status,access_mode,details) values(public.safe_uuid(v_license->>'license_id'),auth.uid(),v_current_role,coalesce(v_license->>'computed_status','unknown'),coalesce(v_license->>'access_mode','locked'),v_license); raise exception 'PLATFORM_ACCESS_LOCKED: %',coalesce(nullif(v_license->>'warning',''),'Access has been restricted by the platform licence administrator.') using errcode='42501'; end if;
  if v_current_role<>'platform_super_admin' and v_write_allowed then current_year:=public.sync_current_academic_year_status(); update public.profiles set last_seen_at=now() where id=auth.uid(); elsif v_current_role='platform_super_admin' then update public.profiles set last_seen_at=now() where id=auth.uid(); end if;
  select jsonb_build_object('id',pr.id,'full_name',pr.full_name,'role',v_current_role,'active',pr.active,'mfa_required',case when v_current_role='platform_super_admin' then true else pr.mfa_required end,'must_change_password',pr.must_change_password,'phone',pr.phone) into p from public.profiles pr where pr.id=auth.uid() and pr.active;
  if not exists(select 1 from public.license_verification_logs v where v.actor_id=auth.uid() and v.computed_status=coalesce(v_license->>'computed_status','unknown') and v.access_mode=coalesce(v_license->>'access_mode','unknown') and v.created_at>now()-interval '15 minutes') then insert into public.license_verification_logs(license_id,actor_id,actor_role,computed_status,access_mode,details) values(public.safe_uuid(v_license->>'license_id'),auth.uid(),v_current_role,coalesce(v_license->>'computed_status','unknown'),coalesce(v_license->>'access_mode','unknown'),jsonb_build_object('write_allowed',v_write_allowed,'read_allowed',v_read_allowed)); end if;
  return jsonb_build_object(
    'profile',p,
    'school',case when v_current_role='platform_super_admin' then (select jsonb_build_object('id',s.id,'school_name',s.school_name,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour) from public.school_settings s limit 1) else (select to_jsonb(s) from public.school_settings s limit 1) end,
    'academic_years',case when v_current_role='platform_super_admin' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(y) order by y.start_date desc nulls last,y.name) from public.academic_years y where y.deleted_at is null),'[]'::jsonb) end,
    'terms',case when v_current_role='platform_super_admin' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(t) order by t.sequence) from public.terms t where t.deleted_at is null),'[]'::jsonb) end,
    'classes',case when v_current_role in ('platform_super_admin','parent_guardian','student') then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(c) order by c.level_order,c.name) from public.classes c where c.deleted_at is null and (v_current_role in ('system_admin','principal','accountant') or public.can_access_class(c.id,false))),'[]'::jsonb) end,
    'subjects',case when v_current_role in ('platform_super_admin','parent_guardian','student','accountant') then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order,s.name) from public.subjects s where s.deleted_at is null and s.active),'[]'::jsonb) end,
    'license',v_license,
    'permissions',jsonb_build_object(
      'manage_licenses',v_current_role='platform_super_admin','manage_users',v_current_role='system_admin' and v_write_allowed,'manage_teachers',v_current_role='system_admin' and v_write_allowed,'manage_headteachers',v_current_role='system_admin' and v_write_allowed,'manage_academics',v_current_role='system_admin' and v_write_allowed,'manage_students',v_current_role='system_admin' and v_write_allowed,'manage_emergency_delegations',v_current_role='system_admin' and v_write_allowed,'acknowledge_emergency_delegations',v_current_role='principal' and v_write_allowed,'remove_students',v_current_role='system_admin' and v_write_allowed,
      'create_reports',(v_current_role in ('class_teacher','subject_teacher') or (v_current_role='system_admin' and v_has_emergency)) and v_write_allowed,'import_scores',(v_current_role in ('class_teacher','subject_teacher') or (v_current_role='system_admin' and v_has_emergency)) and v_write_allowed,'approve_reports',v_current_role='principal' and v_write_allowed,'publish_reports',v_current_role in ('system_admin','class_teacher') and v_write_allowed,'bulk_submit_reports',v_current_role='class_teacher' and v_write_allowed,'bulk_approve_reports',v_current_role='principal' and v_write_allowed,'bulk_publish_reports',v_current_role in ('system_admin','class_teacher') and v_write_allowed,'remove_reports',v_current_role in ('system_admin','class_teacher','subject_teacher') and v_write_allowed,'restore_reports',v_current_role='system_admin' and v_write_allowed,'view_audit',v_current_role='system_admin','run_backup',v_current_role='system_admin','parent_portal',v_current_role='parent_guardian','student_portal',v_current_role='student',
      'manage_finance_staff',v_current_role='system_admin' and v_write_allowed and public.finance_feature_enabled('finance_fees'),'manage_finance',v_current_role='accountant' and v_write_allowed and public.finance_feature_enabled('finance_fees'),'view_finance',v_current_role='accountant' and public.finance_feature_enabled('finance_fees'),'manage_financial_holds',v_current_role='accountant' and v_write_allowed and public.finance_feature_enabled('financial_holds'),'manage_payroll',v_current_role='accountant' and v_write_allowed and public.finance_feature_enabled('payroll')),
    'topics',case when v_current_role='platform_super_admin' then '[]'::jsonb else to_jsonb(public.my_realtime_topics()) end
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_certificate_batch(target_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.license_read_allowed() or not public.has_role(array['system_admin','principal']) then raise exception 'Certificate access denied' using errcode='42501'; end if;
  return (select jsonb_build_object(
    'batch',jsonb_build_object('id',b.id,'certificate_type',b.certificate_type,'type_label',public.certificate_type_label(b.certificate_type),'academic_year_id',b.academic_year_id,'academic_year_name',ay.name,'term_id',b.term_id,'term_name',t.name,'class_id',b.class_id,'class_name',c.name,'award_category_name',ac.name,'title',b.title,'custom_citation',b.custom_citation,'notes',b.notes,'status',b.status,'review_note',b.review_note,'prepared_by_name',pp.full_name,'approved_by_name',pa.full_name,'issued_by_name',pi.full_name,'created_at',b.created_at,'submitted_at',b.submitted_at,'approved_at',b.approved_at,'issued_at',b.issued_at),
    'template',to_jsonb(ct),
    'certificates',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'recipient_kind',x.recipient_kind,'student_id',x.student_id,'teacher_id',x.teacher_id,'source_report_id',x.source_report_id,'certificate_number',x.certificate_number,'verification_token',x.verification_token,'revision_no',x.revision_no,'supersedes_certificate_id',x.supersedes_certificate_id,'recipient_name',x.recipient_name,'recipient_identifier',x.recipient_identifier,'current_class_name',x.current_class_name,'destination_class_name',x.destination_class_name,'academic_year_name',x.academic_year_name,'certificate_title',x.certificate_title,'award_category_name',x.award_category_name,'statement_text',x.statement_text,'issue_date',x.issue_date,'status',x.status,'snapshot',x.snapshot,'pdf_storage_path',x.pdf_storage_path,'pdf_sha256',x.pdf_sha256,'revocation_reason',x.revocation_reason,'replacement_reason',x.replacement_reason,'issued_at',x.issued_at) order by x.recipient_name,x.revision_no) from public.certificates x where x.batch_id=b.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'certificate_id',e.certificate_id,'event_type',e.event_type,'actor_name',p.full_name,'reason',e.reason,'details',e.details,'created_at',e.created_at) order by e.created_at desc) from public.certificate_events e left join public.profiles p on p.id=e.actor_id where e.batch_id=b.id),'[]'::jsonb),
    'principal',(select jsonb_build_object('full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'signature_path',h.signature_path,'signature_updated_at',h.signature_updated_at) from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active' order by case when h.profile_id=b.approved_by then 0 else 1 end,h.created_at limit 1),
    'school',(select to_jsonb(s) from public.school_settings s limit 1)
  ) from public.certificate_batches b join public.academic_years ay on ay.id=b.academic_year_id left join public.terms t on t.id=b.term_id left join public.classes c on c.id=b.class_id left join public.teacher_award_categories ac on ac.id=b.teacher_award_category_id join public.certificate_templates ct on ct.id=b.template_id left join public.profiles pp on pp.id=b.prepared_by left join public.profiles pa on pa.id=b.approved_by left join public.profiles pi on pi.id=b.issued_by where b.id=target_batch_id);
end $function$

CREATE OR REPLACE FUNCTION public.get_certificate_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_certificate_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.license_read_allowed() or not public.has_role(array['system_admin','principal']) then raise exception 'Certificate access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'templates',coalesce((select jsonb_agg(to_jsonb(t) order by t.certificate_type) from public.certificate_templates t),'[]'::jsonb),
    'award_categories',coalesce((select jsonb_agg(to_jsonb(a) order by a.name) from public.teacher_award_categories a where a.active),'[]'::jsonb),
    'settings',(select jsonb_build_object('completion_class_id',s.certificate_completion_class_id,'footer_text',s.certificate_footer_text) from public.school_settings s limit 1),
    'batches',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'certificate_type',b.certificate_type,'type_label',public.certificate_type_label(b.certificate_type),
      'academic_year_id',b.academic_year_id,'academic_year_name',ay.name,'term_id',b.term_id,'term_name',t.name,
      'class_id',b.class_id,'class_name',c.name,'award_category_id',b.teacher_award_category_id,'award_category_name',ac.name,
      'title',b.title,'status',b.status,'notes',b.notes,'review_note',b.review_note,
      'prepared_by_name',pp.full_name,'approved_by_name',pa.full_name,'issued_by_name',pi.full_name,
      'recipient_count',(select count(*) from public.certificates x where x.batch_id=b.id),
      'issued_count',(select count(*) from public.certificates x where x.batch_id=b.id and x.status='issued'),
      'created_at',b.created_at,'submitted_at',b.submitted_at,'approved_at',b.approved_at,'issued_at',b.issued_at
    ) order by b.created_at desc) from public.certificate_batches b
      join public.academic_years ay on ay.id=b.academic_year_id
      left join public.terms t on t.id=b.term_id left join public.classes c on c.id=b.class_id
      left join public.teacher_award_categories ac on ac.id=b.teacher_award_category_id
      left join public.profiles pp on pp.id=b.prepared_by left join public.profiles pa on pa.id=b.approved_by left join public.profiles pi on pi.id=b.issued_by
      where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id)
        and (coalesce(target_certificate_type,'')='' or b.certificate_type=target_certificate_type)
    ),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare target_year_id uuid;term_start date;term_end date;register_row public.class_attendance_registers%rowtype;
begin
  if not public.is_assigned_class_teacher(target_class_id) then raise exception 'You can mark attendance only for your assigned class' using errcode='42501'; end if;
  if target_term_id is null or target_date is null then raise exception 'Term and attendance date are required'; end if;
  select t.academic_year_id,t.start_date,t.end_date into target_year_id,term_start,term_end
  from public.terms t where t.id=target_term_id and t.deleted_at is null;
  if target_year_id is null then raise exception 'Term is unavailable'; end if;
  if term_start is not null and target_date<term_start then raise exception 'Attendance date is before the selected term'; end if;
  if term_end is not null and target_date>term_end then raise exception 'Attendance date is after the selected term'; end if;
  select * into register_row from public.class_attendance_registers r
  where r.term_id=target_term_id and r.class_id=target_class_id and r.attendance_date=target_date;
  return jsonb_build_object(
    'register',case when register_row.id is null then null else to_jsonb(register_row) end,
    'term',jsonb_build_object('id',target_term_id,'start_date',term_start,'end_date',term_end,'academic_year_id',target_year_id),
    'class',(select jsonb_build_object('id',c.id,'name',c.name) from public.classes c where c.id=target_class_id),
    'days_school_opened',(select count(*) from public.class_attendance_registers r where r.term_id=target_term_id and r.class_id=target_class_id),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'enrollment_id',e.id,'student_id',s.id,'admission_no',s.admission_no,
        'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
        'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'roll_number',e.roll_number,
        'attendance_status',coalesce(a.attendance_status,'present'),
        'days_present',counts.days_present,
        'days_school_opened',counts.days_school_opened
      ) order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text)
      from public.enrollments e
      join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active'
      left join public.student_attendance_entries a on a.register_id=register_row.id and a.enrollment_id=e.id
      cross join lateral public.attendance_counts_for_enrollment(e.id,target_term_id) counts
      where e.academic_year_id=target_year_id
        and e.class_id=target_class_id
        and e.deleted_at is null
    ),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_class_timetable_console(target_academic_year_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_can_manage boolean:=public.is_system_admin() and public.current_aal()='aal2';
begin
  if target_academic_year_id is null or target_class_id is null then raise exception 'Academic year and class are required'; end if;
  if not public.can_view_class_timetable(target_class_id) then raise exception 'You are not allowed to view this class timetable' using errcode='42501'; end if;
  perform public.require_license_feature('timetable');
  return jsonb_build_object(
    'academic_year',(select to_jsonb(y) from public.academic_years y where y.id=target_academic_year_id and y.deleted_at is null),
    'class',(select to_jsonb(c) from public.classes c where c.id=target_class_id and c.deleted_at is null),
    'entries',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'academic_year_id',e.academic_year_id,'class_id',e.class_id,'day_of_week',e.day_of_week,
        'period_start',e.period_start,'period_end',e.period_end,'subject_id',e.subject_id,'subject_name',s.name,
        'teacher_id',e.teacher_id,'teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
        'notes',e.notes,'active',e.active,'updated_at',e.updated_at
      ) order by array_position(array['Monday','Tuesday','Wednesday','Thursday','Friday'],e.day_of_week),e.period_start)
      from public.class_timetable_entries e
      join public.subjects s on s.id=e.subject_id
      join public.teachers t on t.id=e.teacher_id
      where e.academic_year_id=target_academic_year_id
        and e.class_id=target_class_id and e.active
        and e.day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday')
    ),'[]'::jsonb),
    'teachers',case when v_can_manage then coalesce((
      select jsonb_agg(distinct jsonb_build_object(
        'id',t.id,'name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no
      ))
      from public.class_subjects cs
      join public.teachers t on t.profile_id=cs.teacher_id
      where cs.class_id=target_class_id and cs.active
        and t.deleted_at is null and t.active and t.employment_status='active'
    ),'[]'::jsonb) else '[]'::jsonb end,
    'subjects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'name',s.name,'code',s.code,'assigned_teacher_profile_id',cs.teacher_id,
        'assigned_teacher_id',t.id,'assigned_teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
      ) order by s.display_order,s.name)
      from public.class_subjects cs
      join public.subjects s on s.id=cs.subject_id and s.deleted_at is null and s.active
      left join public.teachers t on t.profile_id=cs.teacher_id and t.deleted_at is null and t.active and t.employment_status='active'
      where cs.class_id=target_class_id and cs.active
    ),'[]'::jsonb),
    'can_manage',v_can_manage
  );
end
$function$

CREATE OR REPLACE FUNCTION public.get_compliance_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'retention_policies',coalesce((select jsonb_agg(to_jsonb(p) order by p.data_category) from public.data_retention_policies p),'[]'::jsonb),
    'privacy_requests',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'student_id',r.student_id,'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'request_type',r.request_type,'requester_name',r.requester_name,'requester_contact',r.requester_contact,
        'request_details',r.request_details,'status',r.status,'due_at',r.due_at,'outcome',r.outcome,
        'created_at',r.created_at,'completed_at',r.completed_at) order by r.created_at desc)
      from (select * from public.privacy_requests order by created_at desc limit 500) r
      left join public.students s on s.id=r.student_id
    ),'[]'::jsonb),
    'security_events',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'event_type',e.event_type,'severity',e.severity,'source',e.source,'message',e.message,
        'details',e.details,'status',e.status,'created_at',e.created_at,'actor_name',p.full_name,'resolution_note',e.resolution_note)
        order by e.created_at desc)
      from (select * from public.security_events where created_at>=now()-interval '180 days' order by created_at desc limit 500) e
      left join public.profiles p on p.id=e.actor_id
    ),'[]'::jsonb),
    'verification_runs',coalesce((select jsonb_agg(to_jsonb(v) order by v.verified_at desc) from (select * from public.security_verification_runs order by verified_at desc limit 100) v),'[]'::jsonb),
    'open_privacy_requests',(select count(*) from public.privacy_requests where status in ('open','in_review')),
    'overdue_privacy_requests',(select count(*) from public.privacy_requests where status in ('open','in_review') and due_at<now()),
    'open_high_security_events',(select count(*) from public.security_events where status='open' and severity in ('high','critical'))
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_current_principal_signature()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select jsonb_build_object(
    'headteacher_id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'contact',h.phone,
    'signature_path',h.signature_path,
    'signature_updated_at',h.signature_updated_at
  )
  into result
  from public.headteachers h
  where h.deleted_at is null
    and h.active
    and h.employment_status='active'
  order by
    case when btrim(coalesce(h.signature_path,''))<>'' then 0 else 1 end,
    h.updated_at desc,
    h.created_at desc
  limit 1;
  return coalesce(
    result,
    jsonb_build_object(
      'full_name',coalesce((select s.head_name from public.school_settings s order by s.created_at limit 1),'Principal'),
      'signature_path',''
    )
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare termid uuid;
begin
  termid:=target_term_id;
  if termid is null then select id into termid from public.terms where is_active and deleted_at is null limit 1; end if;
  return jsonb_build_object(
    'active_students',(select count(*) from public.students s where s.status='active' and s.deleted_at is null and public.can_view_student(s.id)),
    'active_classes',(select count(*) from public.classes c where c.active and c.deleted_at is null and (public.is_records_manager() or public.can_access_class(c.id,false))),
    'reports',(select count(*) from public.student_reports r where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id)),
    'published',(select count(*) from public.student_reports r where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)),
    'by_status',coalesce((select jsonb_object_agg(status,count_value) from (
      select r.status::text status,count(*) count_value from public.student_reports r
      where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id) group by r.status
    ) q),'{}'::jsonb),
    'class_performance',coalesce((select jsonb_agg(to_jsonb(q) order by q.class_name) from (
      select c.id class_id,c.name class_name,round(avg(sr.total_score),2) average
      from public.subject_results sr
      join public.student_reports r on r.id=sr.report_id
      join public.enrollments e on e.id=r.enrollment_id
      join public.classes c on c.id=e.class_id
      where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)
      group by c.id,c.name
    ) q),'[]'::jsonb),
    'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        c.name class_name,t.name term_name,
        round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id
      join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id
      left join public.subject_results sr on sr.report_id=r.id
      where r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,s.id,c.id,t.id order by r.updated_at desc limit 8
    ) q),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_emergency_delegation_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare actor_role text:=public.current_app_role()::text;
begin
  if actor_role not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'delegations',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select d.*,c.name class_name,t.name term_name,y.name academic_year_name,s.name subject_name,
        dp.full_name delegate_name,public.current_app_role_for(dp.role)::text delegate_role,
        op.full_name original_teacher_name,cp.full_name created_by_name,ap.full_name acknowledged_by_name,rp.full_name revoked_by_name,
        case when d.status='revoked' then 'revoked'
          when now()<d.valid_from then 'scheduled'
          when now()>=d.valid_until then 'expired'
          else 'active' end computed_status
      from public.emergency_academic_delegations d
      join public.classes c on c.id=d.class_id
      join public.terms t on t.id=d.term_id
      join public.academic_years y on y.id=d.academic_year_id
      left join public.subjects s on s.id=d.subject_id
      join public.profiles dp on dp.id=d.delegate_user_id
      left join public.profiles op on op.id=d.original_teacher_id
      left join public.profiles cp on cp.id=d.created_by
      left join public.profiles ap on ap.id=d.principal_acknowledged_by
      left join public.profiles rp on rp.id=d.revoked_by
      order by d.created_at desc limit 300
    ) q),'[]'::jsonb),
    'eligible_users',coalesce((select jsonb_agg(to_jsonb(q) order by lower(q.full_name),q.email) from (
      select p.id,p.full_name,au.email::text,public.current_app_role_for(p.role)::text role,t.staff_no
      from public.profiles p
      left join auth.users au on au.id=p.id
      left join public.teachers t on t.profile_id=p.id and t.deleted_at is null
      where p.active and public.current_app_role_for(p.role)::text in ('system_admin','class_teacher','subject_teacher')
    ) q),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.level_order,q.class_name,q.subject_order,q.subject_name) from (
      select cs.class_id,c.name class_name,c.level_order,cs.subject_id,s.name subject_name,s.code subject_code,s.display_order subject_order,
        cs.teacher_id,p.full_name assigned_teacher_name
      from public.class_subjects cs
      join public.classes c on c.id=cs.class_id
      join public.subjects s on s.id=cs.subject_id
      left join public.profiles p on p.id=cs.teacher_id
      where cs.active and c.active and c.deleted_at is null and s.active and s.deleted_at is null
    ) q),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select e.id,e.delegation_id,e.event_type,e.actor_id,e.report_id,e.subject_id,e.event_reason,e.event_data,e.created_at,
        p.full_name actor_name,s.name subject_name
      from public.emergency_academic_delegation_events e
      left join public.profiles p on p.id=e.actor_id
      left join public.subjects s on s.id=e.subject_id
      order by e.created_at desc limit 300
    ) q),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_headteacher_record(target_headteacher_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() and not exists(
    select 1 from public.headteachers h where h.id=target_headteacher_id and h.profile_id=auth.uid()
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  return (
    select jsonb_build_object(
      'principal',to_jsonb(h)||jsonb_build_object(
        'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
        'profile_email',au.email,'profile_name',p.full_name,
        'profile_role',case when p.id is null then null else public.current_app_role_for(p.role) end
      )
    )
    from public.headteachers h
    left join public.profiles p on p.id=h.profile_id
    left join auth.users au on au.id=h.profile_id
    where h.id=target_headteacher_id
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_id_card_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare year_id uuid:=target_academic_year_id;settings_row jsonb;cards_json jsonb;stats_json jsonb; begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage student ID cards' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit ID card access' using errcode='42501';end if; if year_id is null then select id into year_id from public.academic_years where is_active and deleted_at is null order by start_date desc nulls last,created_at desc limit 1;end if; select to_jsonb(x) into settings_row from public.id_card_settings x limit 1; select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) into cards_json from (select c.id,c.student_id,c.enrollment_id,c.academic_year_id,c.class_id,c.card_number,c.verification_token,c.revision_no,c.supersedes_card_id,c.status,public.id_card_effective_status(c.status,c.expires_on) computed_status,c.issue_date,c.expires_on,c.snapshot,c.issued_at,c.revoked_at,c.revocation_reason,c.replacement_reason,c.snapshot#>>'{student,full_name}' student_name,c.snapshot#>>'{student,admission_no}' admission_no,c.snapshot#>>'{academic,class_name}' class_name,c.snapshot#>>'{academic,academic_year_name}' academic_year_name from public.student_id_cards c where (year_id is null or c.academic_year_id=year_id) and (target_class_id is null or c.class_id=target_class_id) and (target_status is null or target_status='' or public.id_card_effective_status(c.status,c.expires_on)=target_status) order by c.issued_at desc limit 1500) q; select jsonb_build_object('total',count(*),'active',count(*) filter(where public.id_card_effective_status(status,expires_on)='active'),'expired',count(*) filter(where public.id_card_effective_status(status,expires_on)='expired'),'revoked',count(*) filter(where status='revoked'),'replaced',count(*) filter(where status='replaced')) into stats_json from public.student_id_cards c where (year_id is null or c.academic_year_id=year_id) and (target_class_id is null or c.class_id=target_class_id); return jsonb_build_object('generated_at',now(),'settings',coalesce(settings_row,'{}'::jsonb),'academic_year_id',year_id,'stats',stats_json,'cards',cards_json,'feature_enabled',true); end$function$

CREATE OR REPLACE FUNCTION public.get_my_emergency_academic_delegations(target_class_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.valid_until,q.class_name,q.subject_name nulls first),'[]'::jsonb)
  from (
    select d.id,d.delegation_type,d.academic_year_id,d.term_id,d.class_id,d.subject_id,
      d.allow_score_entry,d.allow_class_report_fields,d.valid_from,d.valid_until,d.reason,
      d.principal_acknowledged_at,c.name class_name,t.name term_name,y.name academic_year_name,
      s.name subject_name,op.full_name original_teacher_name,cp.full_name created_by_name
    from public.emergency_academic_delegations d
    join public.classes c on c.id=d.class_id
    join public.terms t on t.id=d.term_id
    join public.academic_years y on y.id=d.academic_year_id
    left join public.subjects s on s.id=d.subject_id
    left join public.profiles op on op.id=d.original_teacher_id
    left join public.profiles cp on cp.id=d.created_by
    where d.delegate_user_id=auth.uid()
      and d.status='active' and now()>=d.valid_from and now()<d.valid_until
      and (target_class_id is null or d.class_id=target_class_id)
      and (target_term_id is null or d.term_id=target_term_id)
  ) q
$function$

CREATE OR REPLACE FUNCTION public.get_my_headteacher_signature()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result jsonb;
begin
  if auth.uid() is null or public.current_app_role()<>'principal' then raise exception 'Access denied' using errcode='42501'; end if;
  select jsonb_build_object('linked',true,'headteacher_id',h.id,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'contact',h.phone,'signature_path',h.signature_path,'signature_updated_at',h.signature_updated_at,'updated_at',h.updated_at)
  into result from public.headteachers h where h.profile_id=auth.uid() and h.deleted_at is null and h.active order by h.updated_at desc limit 1;
  return coalesce(result,jsonb_build_object('linked',false,'full_name',(select p.full_name from public.profiles p where p.id=auth.uid()),'signature_path',''));
end $function$

CREATE OR REPLACE FUNCTION public.get_my_student_portal()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; h jsonb;
begin
 if public.current_app_role()<>'student' then raise exception 'Student access required' using errcode='42501'; end if;
 select id into sid from public.students where profile_id=auth.uid() and deleted_at is null order by updated_at desc limit 1;
 if sid is null then return jsonb_build_object('linked',false,'student',null,'fee_statement',null,'reports','[]'::jsonb); end if;
 h:=public.finance_student_hold_status(sid);
 return jsonb_build_object('linked',true,
  'student',(select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'status',s.status,'class_name',coalesce(c.name,'')) from public.students s left join lateral(select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1) ce on true left join public.classes c on c.id=ce.class_id where s.id=sid),
  'financial_hold',h,'fee_statement',public.finance_student_statement(sid),
  'reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'report_number',r.report_number,'term_name',t.name,'academic_year_name',y.name,'published_at',r.published_at,'locked',coalesce((h->>'block_grade_details')::boolean,false),'average',case when coalesce((h->>'block_grade_details')::boolean,false) then null else coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0) end,'publication',case when coalesce((h->>'block_report_pdf')::boolean,false) then null else (select jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at) from public.report_publications rp where rp.report_id=r.id and rp.revoked_at is null order by rp.published_at desc limit 1) end) order by y.start_date desc nulls last,t.sequence desc) from public.enrollments e join public.student_reports r on r.enrollment_id=e.id and r.status='published' and r.deleted_at is null join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id where e.student_id=sid and e.deleted_at is null),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.get_my_student_portal_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  sid uuid;
  current_enrollment_id uuid;
  current_class_id uuid;
  current_year_id uuid;
  current_roll_number integer;
  current_class_name text;
  current_year_name text;
  current_year_start date;
  current_term_id uuid;
  current_term_name text;
  current_term_sequence smallint;
  h jsonb;
  finance_enabled boolean:=public.license_feature_enabled('finance_statements');
  timetable_enabled boolean:=public.license_feature_enabled('timetable');
  attendance_enabled boolean:=public.license_feature_enabled('attendance');
  notifications_enabled boolean:=public.license_feature_enabled('notifications');
begin
  if public.current_app_role()::text<>'student' then
    raise exception 'Student access required' using errcode='42501';
  end if;

  select s.id into sid
  from public.students s
  where s.profile_id=auth.uid() and s.deleted_at is null
  order by s.updated_at desc
  limit 1;

  if sid is null then
    return jsonb_build_object(
      'linked',false,
      'student',null,
      'account',(select jsonb_build_object(
        'email',coalesce(auth.jwt()->>'email',''),
        'phone',p.phone,
        'mfa_required',p.mfa_required,
        'must_change_password',p.must_change_password,
        'last_seen_at',p.last_seen_at
      ) from public.profiles p where p.id=auth.uid()),
      'features',jsonb_build_object(
        'finance',finance_enabled,
        'timetable',timetable_enabled,
        'attendance',attendance_enabled,
        'notifications',notifications_enabled
      ),
      'fee_statement',null,
      'reports','[]'::jsonb,
      'attendance',null,
      'timetable',null,
      'notifications',jsonb_build_object('unread',0,'total',0,'recent','[]'::jsonb)
    );
  end if;

  select e.id,e.class_id,e.academic_year_id,e.roll_number,c.name::text,y.name::text,y.start_date
  into current_enrollment_id,current_class_id,current_year_id,current_roll_number,current_class_name,current_year_name,current_year_start
  from public.enrollments e
  join public.classes c on c.id=e.class_id and c.deleted_at is null
  join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
  where e.student_id=sid and e.deleted_at is null
  order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
  limit 1;

  if current_year_id is not null then
    select t.id,t.name::text,t.sequence
    into current_term_id,current_term_name,current_term_sequence
    from public.terms t
    where t.academic_year_id=current_year_id and t.deleted_at is null
    order by t.is_active desc,t.sequence desc
    limit 1;
  end if;

  h:=public.finance_student_hold_status(sid);

  return jsonb_build_object(
    'linked',true,
    'student',(select jsonb_build_object(
      'id',s.id,
      'admission_no',s.admission_no,
      'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'first_name',s.first_name,
      'middle_name',s.middle_name,
      'last_name',s.last_name,
      'gender',s.gender,
      'date_of_birth',s.date_of_birth,
      'status',s.status,
      'photo_url',s.photo_url,
      'guardian_name',s.guardian_name,
      'guardian_phone',s.guardian_phone,
      'guardian_email',s.guardian_email,
      'enrollment_id',current_enrollment_id,
      'class_id',current_class_id,
      'class_name',coalesce(current_class_name,''),
      'roll_number',current_roll_number,
      'academic_year_id',current_year_id,
      'academic_year_name',coalesce(current_year_name,''),
      'term_id',current_term_id,
      'term_name',coalesce(current_term_name,''),
      'class_teacher',(select concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
        from public.classes c
        left join public.teachers t on t.id=c.class_teacher_record_id and t.deleted_at is null
        where c.id=current_class_id)
    ) from public.students s where s.id=sid),
    'account',(select jsonb_build_object(
      'email',coalesce(auth.jwt()->>'email',''),
      'phone',p.phone,
      'mfa_required',p.mfa_required,
      'must_change_password',p.must_change_password,
      'last_seen_at',p.last_seen_at
    ) from public.profiles p where p.id=auth.uid()),
    'features',jsonb_build_object(
      'finance',finance_enabled,
      'timetable',timetable_enabled,
      'attendance',attendance_enabled,
      'notifications',notifications_enabled
    ),
    'financial_hold',h,
    'fee_statement',case when finance_enabled then public.finance_student_statement(sid) else null end,
    'reports',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'report_number',r.report_number,
        'term_name',t.name,
        'term_sequence',t.sequence,
        'academic_year_name',y.name,
        'academic_year_start',y.start_date,
        'published_at',r.published_at,
        'locked',coalesce((h->>'block_grade_details')::boolean,false),
        'average',case when coalesce((h->>'block_grade_details')::boolean,false) then null else coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0) end,
        'attendance_present',r.days_present,
        'attendance_total',r.days_school_opened,
        'publication',case when coalesce((h->>'block_report_pdf')::boolean,false) then null else (
          select jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at)
          from public.report_publications rp
          where rp.report_id=r.id and rp.revoked_at is null
          order by rp.published_at desc
          limit 1
        ) end
      ) order by y.start_date desc nulls last,t.sequence desc)
      from public.enrollments e
      join public.student_reports r on r.enrollment_id=e.id and r.status='published' and r.deleted_at is null
      join public.terms t on t.id=r.term_id
      join public.academic_years y on y.id=t.academic_year_id
      where e.student_id=sid and e.deleted_at is null
    ),'[]'::jsonb),
    'attendance',case when attendance_enabled and current_enrollment_id is not null then jsonb_build_object(
      'current',case when current_term_id is null then null else (
        select jsonb_build_object(
          'term_id',current_term_id,
          'term_name',current_term_name,
          'class_name',current_class_name,
          'days_opened',count(distinct r.id),
          'present',count(a.id) filter(where a.attendance_status='present'),
          'late',count(a.id) filter(where a.attendance_status='late'),
          'absent',count(a.id) filter(where a.attendance_status='absent'),
          'excused',count(a.id) filter(where a.attendance_status='excused'),
          'days_present',count(a.id) filter(where a.attendance_status in ('present','late')),
          'percentage',case when count(distinct r.id)>0 then round((count(a.id) filter(where a.attendance_status in ('present','late')))::numeric*100/count(distinct r.id),1) else 0 end
        )
        from public.class_attendance_registers r
        left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=current_enrollment_id
        where r.term_id=current_term_id and r.class_id=current_class_id
      ) end,
      'history',coalesce((
        select jsonb_agg(jsonb_build_object(
          'term_id',q.term_id,
          'term_name',q.term_name,
          'term_sequence',q.term_sequence,
          'academic_year_name',q.academic_year_name,
          'class_name',q.class_name,
          'days_opened',q.days_opened,
          'present',q.present,
          'late',q.late,
          'absent',q.absent,
          'excused',q.excused,
          'days_present',q.days_present,
          'percentage',q.percentage
        ) order by q.year_start desc,q.term_sequence desc)
        from (
          select
            t.id as term_id,
            t.name::text as term_name,
            t.sequence as term_sequence,
            y.name::text as academic_year_name,
            y.start_date as year_start,
            c.name::text as class_name,
            count(distinct r.id)::integer as days_opened,
            count(a.id) filter(where a.attendance_status='present')::integer as present,
            count(a.id) filter(where a.attendance_status='late')::integer as late,
            count(a.id) filter(where a.attendance_status='absent')::integer as absent,
            count(a.id) filter(where a.attendance_status='excused')::integer as excused,
            count(a.id) filter(where a.attendance_status in ('present','late'))::integer as days_present,
            case when count(distinct r.id)>0 then round((count(a.id) filter(where a.attendance_status in ('present','late')))::numeric*100/count(distinct r.id),1) else 0 end as percentage
          from public.enrollments e
          join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
          join public.classes c on c.id=e.class_id and c.deleted_at is null
          join public.terms t on t.academic_year_id=e.academic_year_id and t.deleted_at is null
          left join public.class_attendance_registers r on r.term_id=t.id and r.class_id=e.class_id
          left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=e.id
          where e.student_id=sid and e.deleted_at is null
          group by t.id,t.name,t.sequence,y.name,y.start_date,c.name
        ) q
      ),'[]'::jsonb)
    ) else null end,
    'timetable',case when timetable_enabled and current_year_id is not null and current_class_id is not null then jsonb_build_object(
      'academic_year_id',current_year_id,
      'academic_year_name',current_year_name,
      'class_id',current_class_id,
      'class_name',current_class_name,
      'entries',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',e.id,
          'day_of_week',e.day_of_week,
          'period_start',e.period_start,
          'period_end',e.period_end,
          'subject_id',e.subject_id,
          'subject_name',s.name,
          'teacher_id',e.teacher_id,
          'teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
          'notes',e.notes
        ) order by array_position(array['Monday','Tuesday','Wednesday','Thursday','Friday'],e.day_of_week),e.period_start)
        from public.class_timetable_entries e
        join public.subjects s on s.id=e.subject_id and s.deleted_at is null
        join public.teachers t on t.id=e.teacher_id and t.deleted_at is null
        where e.academic_year_id=current_year_id and e.class_id=current_class_id and e.active
          and e.day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday')
      ),'[]'::jsonb)
    ) else null end,
    'notifications',case when notifications_enabled then jsonb_build_object(
      'unread',(select count(*) from public.notifications n where n.recipient_id=auth.uid() and n.read_at is null),
      'total',(select count(*) from public.notifications n where n.recipient_id=auth.uid()),
      'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
        select n.id,n.title,n.body,n.category,n.entity_type,n.entity_id,n.read_at,n.created_at
        from public.notifications n
        where n.recipient_id=auth.uid()
        order by n.created_at desc
        limit 8
      ) q),'[]'::jsonb)
    ) else jsonb_build_object('unread',0,'total',0,'recent','[]'::jsonb) end
  );
end
$function$

CREATE OR REPLACE FUNCTION public.get_my_teacher_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare tid uuid;
begin
  if auth.uid() is null or public.current_app_role() not in ('class_teacher','subject_teacher') then raise exception 'Teacher access required' using errcode='42501';end if;
  select id into tid from public.teachers where profile_id=auth.uid() and deleted_at is null order by active desc,updated_at desc limit 1;
  if tid is null then return jsonb_build_object('linked',false,'teacher',null,'classes','[]'::jsonb,'subjects','[]'::jsonb,'assigned_class_count',0);end if;
  return (select jsonb_build_object(
    'linked',true,
    'teacher',to_jsonb(t)||jsonb_build_object('full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'profile_email',au.email),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb),
    'assigned_class_count',(select count(distinct x.class_id) from (select c.id class_id from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null union select cs.class_id from public.class_subjects cs where cs.teacher_id=t.profile_id and cs.active) x)
  ) from public.teachers t left join auth.users au on au.id=t.profile_id where t.id=tid);
end$function$

CREATE OR REPLACE FUNCTION public.get_platform_license_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb;
begin
  perform public.require_platform_super_admin();s:=public.license_snapshot_for_role('system_admin');return jsonb_build_object(
    'school',(select jsonb_build_object('id',x.id,'school_name',x.school_name,'logo_url',x.logo_url,'email',x.email,'phone',x.phone) from public.school_settings x limit 1),
    'snapshot',s,'license',(select to_jsonb(l)-'license_key_hash' from public.school_licenses l order by l.created_at limit 1),
    'plans',coalesce((select jsonb_agg(to_jsonb(p) order by p.active desc,p.name) from public.license_plans p),'[]'::jsonb),
    'feature_catalog',coalesce((select jsonb_agg(to_jsonb(f) order by f.category,f.name) from public.license_feature_catalog f where f.active),'[]'::jsonb),
    'plan_revisions',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from (select * from public.license_plan_revisions order by created_at desc limit 100) r),'[]'::jsonb),
    'active_override',(select to_jsonb(o) from public.license_entitlement_overrides o join public.school_licenses l on l.id=o.license_id where o.active order by o.created_at desc limit 1),
    'distribution_authority',(select to_jsonb(a) from public.platform_distribution_authorities a where a.actor_id=auth.uid() limit 1),
    'distribution_authorities',coalesce((select jsonb_agg(to_jsonb(q) order by lower(q.full_name)) from (select a.*,p.full_name from public.platform_distribution_authorities a join public.profiles p on p.id=a.actor_id) q),'[]'::jsonb),
    'usage',jsonb_build_object('active_students',(select count(*) from public.students x where x.status='active' and x.deleted_at is null),'active_teachers',(select count(*) from public.teachers x where x.active and x.deleted_at is null),'active_system_admins',(select count(*) from public.profiles x where x.active and public.current_app_role_for(x.role)::text='system_admin'),'active_guardians',(select count(*) from public.profiles x where x.active and public.current_app_role_for(x.role)::text='parent_guardian'),'storage_mb',(select round(coalesce(sum(case when coalesce(x.metadata->>'size','')~'^\d+$' then (x.metadata->>'size')::numeric else 0 end),0)/1048576.0,2) from storage.objects x where x.bucket_id in ('student-photos','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs')),'published_reports',(select count(*) from public.student_reports x where x.status='published')),
    'active_locks',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.platform_access_locks x where x.active and (x.ends_at is null or x.ends_at>now())),'[]'::jsonb),
    'recent_events',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select e.*,coalesce(p.full_name,'System') actor_name from public.license_events e left join public.profiles p on p.id=e.actor_id order by e.created_at desc limit 200) q),'[]'::jsonb),
    'verification_history',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select * from public.license_verification_logs order by created_at desc limit 100) q),'[]'::jsonb),
    'archives',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.platform_audit_archives a where a.archive_scope='licensing'),'[]'::jsonb),
    'platform_admins',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',u.email,'active',p.active,'mfa_required',p.mfa_required,'last_seen_at',p.last_seen_at,'created_at',p.created_at) order by lower(p.full_name)) from public.profiles p left join auth.users u on u.id=p.id where public.current_app_role_for(p.role)::text='platform_super_admin'),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.get_recovery_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'tests',coalesce((select jsonb_agg(to_jsonb(r) order by r.started_at desc) from (select * from public.recovery_test_runs order by started_at desc limit 50) r),'[]'::jsonb),
    'latest_passed',(select max(completed_at) from public.recovery_test_runs where status='passed'),
    'latest_failed',(select max(completed_at) from public.recovery_test_runs where status='failed')
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_report_correction_console(target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'requests',coalesce((select jsonb_agg(jsonb_build_object(
      'id',q.id,'report_id',q.report_id,'status',q.status,'reason',q.reason,'requested_fields',q.requested_fields,
      'requested_by',q.requested_by,'requester_name',rp.full_name,'reviewed_by',q.reviewed_by,'reviewer_name',vp.full_name,
      'review_note',q.review_note,'created_at',q.created_at,'reviewed_at',q.reviewed_at,'applied_at',q.applied_at,
      'report_number',r.report_number,'report_status',r.status,'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'class_id',e.class_id,'class_name',c.name,'term_id',r.term_id,'term_name',t.name
    ) order by q.created_at desc)
    from public.report_correction_requests q
    join public.student_reports r on r.id=q.report_id
    join public.enrollments e on e.id=r.enrollment_id
    join public.students s on s.id=e.student_id
    join public.classes c on c.id=e.class_id
    join public.terms t on t.id=r.term_id
    left join public.profiles rp on rp.id=q.requested_by left join public.profiles vp on vp.id=q.reviewed_by
    where (target_term_id is null or r.term_id=target_term_id)
      and (target_class_id is null or e.class_id=target_class_id)
      and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(e.class_id,false))),'[]'::jsonb),
    'pending_count',(select count(*) from public.report_correction_requests q join public.student_reports r on r.id=q.report_id join public.enrollments e on e.id=r.enrollment_id where q.status='pending' and (target_term_id is null or r.term_id=target_term_id) and (target_class_id is null or e.class_id=target_class_id) and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(e.class_id,false)))
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_report_editor(target_report_id uuid DEFAULT NULL::uuid, target_enrollment_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  rid uuid:=target_report_id;
  enrollmentid uuid:=target_enrollment_id;
  termid uuid:=target_term_id;
  classid uuid;
  yearid uuid;
  report_json jsonb;
  student_json jsonb;
  canedit boolean;
  canfields boolean;
begin
  if rid is not null then
    if not public.can_view_report_internal(rid) then raise exception 'Access denied' using errcode='42501'; end if;
    select r.enrollment_id,r.term_id,e.class_id,e.academic_year_id,to_jsonb(r)
      into enrollmentid,termid,classid,yearid,report_json
    from public.student_reports r
    join public.enrollments e on e.id=r.enrollment_id
    where r.id=rid and r.deleted_at is null;
    if report_json is null then raise exception 'Report not found'; end if;
  else
    if public.current_app_role()::text not in ('system_admin','principal','class_teacher','subject_teacher') then
      raise exception 'Access denied' using errcode='42501';
    end if;
    select e.class_id,e.academic_year_id into classid,yearid
    from public.enrollments e where e.id=enrollmentid and e.deleted_at is null;
    if classid is null or not public.can_create_report_for_class_term(classid,termid) then raise exception 'Access denied' using errcode='42501'; end if;
    if not exists(select 1 from public.terms t where t.id=termid and t.academic_year_id=yearid and t.deleted_at is null) then
      raise exception 'Term and enrolment academic year do not match';
    end if;
    select to_jsonb(r) into report_json from public.student_reports r
    where r.enrollment_id=enrollmentid and r.term_id=termid and r.deleted_at is null;
    if report_json is not null then rid:=(report_json->>'id')::uuid;
    else
      report_json:=jsonb_build_object('id',null,'enrollment_id',enrollmentid,'term_id',termid,'status','draft','version',0,
        'days_school_opened',0,'days_present',0,'attitude','','conduct','','interest','','teacher_comment','','head_comment','',
        'promoted_to_class_id',null);
    end if;
  end if;

  select jsonb_build_object(
    'id',s.id,'admission_no',s.admission_no,'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
    'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'gender',s.gender,'date_of_birth',s.date_of_birth,'photo_url',s.photo_url,
    'class_id',e.class_id,'class_name',c.name,'academic_year_id',e.academic_year_id,'academic_year_name',y.name,'roll_number',e.roll_number,
    'term_name',t.name,'term_sequence',t.sequence,'next_term_begins',t.next_term_begins
  ) into student_json
  from public.enrollments e
  join public.students s on s.id=e.student_id
  join public.classes c on c.id=e.class_id
  join public.academic_years y on y.id=e.academic_year_id
  join public.terms t on t.id=termid
  where e.id=enrollmentid;

  canedit:=case when rid is null then public.can_create_report_for_class_term(classid,termid) else public.can_edit_report(rid) end;
  canfields:=(public.can_manage_class_report_fields_for_term(classid,termid)
    or (rid is not null and public.has_approved_report_correction(rid) and public.can_manage_class_report_fields_scope(classid,termid)))
    and coalesce(report_json->>'status','draft') in ('draft','returned','withdrawn');

  return jsonb_build_object(
    'report',report_json,
    'student',student_json,
    'can_edit',canedit,
    'can_edit_fields',canfields,
    'allowed_transitions',case when rid is null then '[]'::jsonb else to_jsonb(public.allowed_report_transitions(rid)) end,
    'subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.display_order,q.subject_name) from (
      select sb.id subject_id,sb.code subject_code,sb.name subject_name,sb.display_order,
        (public.can_score_class_subject_for_term(classid,sb.id,termid)
          or (rid is not null and public.has_approved_report_correction(rid) and public.can_score_class_subject_scope(classid,sb.id,termid)))
          and coalesce(report_json->>'status','draft') in ('draft','returned','withdrawn') can_score,
        coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid)) scheme_id,
        sc.name scheme_name,sr.id result_id,
        coalesce(sr.total_score,0) total_score,coalesce(sr.grade,'') grade,coalesce(sr.remark,'') remark,
        coalesce(sr.grade_point,0) grade_point,coalesce(sr.teacher_initials,'') teacher_initials,
        coalesce((select jsonb_agg(jsonb_build_object(
          'component_id',ac.id,'name',ac.name,'code',ac.code,'maximum_score',ac.maximum_score,
          'weight',ac.weight,'required',ac.required,'display_order',ac.display_order,
          'raw_score',coalesce(se.raw_score,0),'weighted_score',coalesce(se.weighted_score,0)
        ) order by ac.display_order,ac.name)
        from public.assessment_components ac
        left join public.assessment_score_entries se on se.component_id=ac.id and se.subject_result_id=sr.id
        where ac.scheme_id=coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid))),'[]'::jsonb) components
      from public.class_subjects cs
      join public.subjects sb on sb.id=cs.subject_id
      left join public.subject_results sr on sr.report_id=rid and sr.subject_id=sb.id
      left join public.assessment_schemes sc on sc.id=coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid))
      where cs.class_id=classid and cs.active and sb.active and sb.deleted_at is null
    ) q),'[]'::jsonb),
    'emergency_delegations',public.get_my_emergency_academic_delegations(classid,termid),
    'workflow',case when rid is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select w.*,p.full_name actor_name from public.report_workflow_events w
      left join public.profiles p on p.id=w.actor_id where w.report_id=rid
    ) q),'[]'::jsonb) end,
    'publications',case when rid is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(p) order by p.published_at desc)
      from public.report_publications p where p.report_id=rid),'[]'::jsonb) end
  );
end
$function$

CREATE OR REPLACE FUNCTION public.get_report_grading_guide(target_report_id uuid DEFAULT NULL::uuid, target_enrollment_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_report public.student_reports;
  v_class_id uuid;
  v_year_id uuid;
  v_snapshot jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if target_report_id is not null then
    if not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if;
    select r.* into v_report from public.student_reports r where r.id=target_report_id and r.deleted_at is null;
    if v_report.id is null then raise exception 'Report not found'; end if;
    if v_report.status in ('submitted','class_reviewed','approved','published')
       and jsonb_typeof(v_report.grading_scale_snapshot)='object'
       and jsonb_array_length(coalesce(v_report.grading_scale_snapshot->'rows','[]'::jsonb))>0 then
      return v_report.grading_scale_snapshot;
    end if;
    return public.resolve_report_grading_guide(v_report.id);
  end if;
  if target_enrollment_id is null or target_term_id is null then
    raise exception 'Report, enrolment, or term scope is required';
  end if;
  select e.class_id,e.academic_year_id into v_class_id,v_year_id
  from public.enrollments e
  where e.id=target_enrollment_id and e.deleted_at is null;
  if v_class_id is null then raise exception 'Enrolment not found'; end if;
  if not public.can_create_report_for_class_term(v_class_id,target_term_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.terms t
    where t.id=target_term_id and t.academic_year_id=v_year_id and t.deleted_at is null
  ) then raise exception 'Term and enrolment academic year do not match'; end if;
  return public.resolve_grading_guide(v_year_id,v_class_id);
end $function$

CREATE OR REPLACE FUNCTION public.get_report_headteacher_signature(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result jsonb;
begin
  if not public.can_view_report_internal(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select jsonb_build_object(
    'headteacher_id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'contact',h.phone,
    'signature_path',h.signature_path,
    'signature_updated_at',h.signature_updated_at
  ) into result
  from public.headteachers h
  where h.deleted_at is null and h.active and h.employment_status='active'
  order by case when btrim(coalesce(h.signature_path,''))<>'' then 0 else 1 end,
           h.updated_at desc,h.created_at desc
  limit 1;
  return coalesce(result,jsonb_build_object(
    'full_name',coalesce((select s.head_name from public.school_settings s order by s.created_at limit 1),'Principal'),
    'signature_path',''
  ));
end
$function$

CREATE OR REPLACE FUNCTION public.get_report_revisions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_report_internal(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',rr.id,'version',rr.version,'reason',rr.reason,'actor_id',rr.actor_id,
    'actor_name',p.full_name,'created_at',rr.created_at,'snapshot',rr.snapshot
  ) order by rr.version desc)
  from public.report_revisions rr left join public.profiles p on p.id=rr.actor_id
  where rr.report_id=target_report_id),'[]'::jsonb);
end
$function$

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
end $function$

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
end $function$

CREATE OR REPLACE FUNCTION public.get_school_license_capacity_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_catalog', 'extensions'
AS $function$ declare actor_role text:=coalesce(public.current_app_role()::text,'');snapshot jsonb;entitlement jsonb;plan_data jsonb;students_count bigint:=0;teachers_count bigint:=0;admins_count bigint:=0;guardians_count bigint:=0;published_reports_count bigint:=0;storage_bytes bigint:=0;storage_mb numeric:=0;storage_breakdown jsonb:='[]'::jsonb;verification_rows jsonb:='[]'::jsonb; begin if actor_role<>'system_admin' then raise exception 'School System Administrator access required' using errcode='42501';end if;snapshot:=public.license_snapshot_for_role('system_admin');entitlement:=public.license_effective_entitlement();plan_data:=coalesce(entitlement->'plan',snapshot->'plan','{}'::jsonb);select count(*) into students_count from public.students where status='active' and deleted_at is null;select count(*) into teachers_count from public.teachers where active and deleted_at is null;select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';select count(*) into published_reports_count from public.student_reports where status='published';select coalesce(sum(case when coalesce(metadata->>'size','')~'^\d+$' then (metadata->>'size')::bigint else 0 end),0) into storage_bytes from storage.objects where bucket_id in ('student-photos','staff-photos','school-branding','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs');storage_mb:=round(storage_bytes/1048576.0,2);select coalesce(jsonb_agg(jsonb_build_object('bucket_id',bucket_id,'object_count',object_count,'bytes',bucket_bytes,'storage_mb',round(bucket_bytes/1048576.0,2)) order by bucket_id),'[]'::jsonb) into storage_breakdown from (select bucket_id,count(*)::bigint object_count,coalesce(sum(case when coalesce(metadata->>'size','')~'^\d+$' then (metadata->>'size')::bigint else 0 end),0)::bigint bucket_bytes from storage.objects where bucket_id in ('student-photos','staff-photos','school-branding','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs') group by bucket_id)bucket_usage;select coalesce(jsonb_agg(jsonb_build_object('created_at',created_at,'computed_status',computed_status,'access_mode',access_mode,'verification_source',verification_source) order by created_at desc),'[]'::jsonb) into verification_rows from (select created_at,computed_status,access_mode,verification_source from public.license_verification_logs order by created_at desc limit 20)verification_history; return jsonb_build_object('read_only',true,'generated_at',now(),'school',(select jsonb_build_object('id',id,'school_name',school_name,'logo_url',logo_url,'email',email,'phone',phone) from public.school_settings limit 1),'snapshot',snapshot,'plan',plan_data,'capacity',jsonb_build_array(jsonb_build_object('key','students','label','Active students','unit','records','used',students_count,'limit',nullif(plan_data->>'max_students','')::bigint),jsonb_build_object('key','teachers','label','Active teachers','unit','records','used',teachers_count,'limit',nullif(plan_data->>'max_teachers','')::bigint),jsonb_build_object('key','system_admins','label','System Administrators','unit','accounts','used',admins_count,'limit',nullif(plan_data->>'max_system_admins','')::bigint),jsonb_build_object('key','guardians','label','Guardians','unit','accounts','used',guardians_count,'limit',nullif(plan_data->>'max_guardians','')::bigint),jsonb_build_object('key','storage','label','School Storage','unit','MB','used',storage_mb,'limit',nullif(plan_data->>'max_storage_mb','')::numeric)),'usage',jsonb_build_object('active_students',students_count,'active_teachers',teachers_count,'active_system_admins',admins_count,'active_guardians',guardians_count,'published_reports',published_reports_count,'storage_bytes',storage_bytes,'storage_mb',storage_mb),'storage_buckets',storage_breakdown,'feature_flags',coalesce(plan_data->'feature_flags','{}'::jsonb),'verification_history',verification_rows); end$function$

CREATE OR REPLACE FUNCTION public.get_school_prospectus_console(target_academic_year_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare yearid uuid:=target_academic_year_id; rows jsonb;
begin
 if not public.is_system_admin() then raise exception 'School System Administrator access required' using errcode='42501';end if;perform public.require_license_feature('school_prospectus');
 if yearid is null then select id into yearid from public.academic_years where deleted_at is null order by is_current desc,coalesce(start_date,'1900-01-01') desc,created_at desc limit 1;end if;
 select coalesce(jsonb_agg(public.build_school_prospectus_snapshot(p.id)||jsonb_build_object('revision_history',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'revision_no',r.revision_no,'reason',r.reason,'published_at',r.published_at) order by r.revision_no desc) from public.school_prospectus_revisions r where r.prospectus_id=p.id),'[]'::jsonb)) order by p.class_range),'[]'::jsonb) into rows from public.school_prospectuses p where p.academic_year_id=yearid;
 return jsonb_build_object('academic_year_id',yearid,'prospectuses',rows,'can_manage',true,'generated_at',now());
end$function$

CREATE OR REPLACE FUNCTION public.get_staff_id_card_console(target_staff_type text DEFAULT NULL::text, target_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare settings_row jsonb;cards_json jsonb;stats_json jsonb;kind text:=lower(btrim(coalesce(target_staff_type,'')));
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage staff ID cards' using errcode='42501';end if;perform public.require_license_feature('staff_id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit staff ID card access' using errcode='42501';end if;if kind not in ('','teacher','principal') then raise exception 'Invalid staff type filter';end if;select to_jsonb(x) into settings_row from public.id_card_settings x limit 1;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) into cards_json from (select c.id,c.staff_type,c.teacher_id,c.headteacher_id,c.academic_year_id,c.card_number,c.verification_token,c.revision_no,c.supersedes_card_id,c.status,public.id_card_effective_status(c.status,c.expires_on) computed_status,c.issue_date,c.expires_on,c.snapshot,c.issued_at,c.revoked_at,c.revocation_reason,c.replacement_reason,c.snapshot#>>'{staff,full_name}' staff_name,c.snapshot#>>'{staff,staff_no}' staff_no,c.snapshot#>>'{staff,role}' staff_role,c.snapshot#>>'{academic,academic_year_name}' academic_year_name from public.staff_id_cards c where (kind='' or c.staff_type=kind) and (target_status is null or target_status='' or public.id_card_effective_status(c.status,c.expires_on)=target_status) order by c.issued_at desc limit 1500)q;
  select jsonb_build_object('total',count(*),'active',count(*) filter(where public.id_card_effective_status(status,expires_on)='active'),'expired',count(*) filter(where public.id_card_effective_status(status,expires_on)='expired'),'revoked',count(*) filter(where status='revoked'),'replaced',count(*) filter(where status='replaced')) into stats_json from public.staff_id_cards c where kind='' or c.staff_type=kind;
  return jsonb_build_object('generated_at',now(),'settings',coalesce(settings_row,'{}'::jsonb),'stats',stats_json,'cards',cards_json,'feature_enabled',true);
end$function$

CREATE OR REPLACE FUNCTION public.get_student_academic_history(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_student_history(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'transcript',public.build_student_transcript_snapshot(target_student_id),
    'current_issuance',coalesce((
      select jsonb_build_object(
        'id',i.id,'transcript_number',i.transcript_number,'verification_token',i.verification_token,
        'purpose',i.purpose,'status',i.status,'issued_at',i.issued_at,'issuer_name',p.full_name,
        'snapshot_checksum',i.snapshot_checksum,'academic_period_count',i.academic_period_count,
        'latest_academic_year',i.latest_academic_year,'latest_term',i.latest_term,'latest_class',i.latest_class,
        'template_version',i.template_version,'snapshot',i.snapshot
      )
      from public.transcript_issuances i
      left join public.profiles p on p.id=i.issued_by
      where i.student_id=target_student_id and i.status='valid'
      order by i.issued_at desc
      limit 1
    ),'null'::jsonb),
    'issuances',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'transcript_number',i.transcript_number,'verification_token',i.verification_token,
        'purpose',i.purpose,'status',i.status,'issued_at',i.issued_at,'issuer_name',p.full_name,
        'snapshot_checksum',i.snapshot_checksum,'academic_period_count',i.academic_period_count,
        'latest_academic_year',i.latest_academic_year,'latest_term',i.latest_term,'latest_class',i.latest_class,
        'template_version',i.template_version,'revoked_at',i.revoked_at,'revocation_reason',i.revocation_reason
      ) order by i.issued_at desc)
      from public.transcript_issuances i
      left join public.profiles p on p.id=i.issued_by
      where i.student_id=target_student_id
    ),'[]'::jsonb)
  );
end
$function$

CREATE OR REPLACE FUNCTION public.get_student_record(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'student',(select to_jsonb(s) from public.students s where s.id=target_student_id and s.deleted_at is null),
    'enrollments',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc nulls last) from (
      select e.*,c.name class_name,y.name academic_year_name,y.start_date
      from public.enrollments e join public.classes c on c.id=e.class_id
      join public.academic_years y on y.id=e.academic_year_id
      where e.student_id=target_student_id and e.deleted_at is null
    ) q),'[]'::jsonb),
    'guardians',coalesce((select jsonb_agg(to_jsonb(q) order by q.is_primary desc,q.full_name) from (
      select g.*,gl.auth_user_id,gl.can_view_reports,gl.can_receive_notifications,gl.verified_at
      from public.student_guardians g join public.guardian_links gl on gl.guardian_id=g.id
      where gl.student_id=target_student_id
    ) q),'[]'::jsonb),
    'reports',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc,q.sequence desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,t.name term_name,t.sequence,
        y.name academic_year_name,y.start_date,c.name class_name,
        round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id
      join public.classes c on c.id=e.class_id left join public.subject_results sr on sr.report_id=r.id
      where e.student_id=target_student_id and r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,t.id,y.id,c.id
    ) q),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_student_record_v5(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'student',(select to_jsonb(s)||(jsonb_build_object('archived',s.deleted_at is not null)) from public.students s where s.id=target_student_id),
    'enrollments',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc nulls last) from (
      select e.*,c.name class_name,y.name academic_year_name,y.start_date
      from public.enrollments e join public.classes c on c.id=e.class_id
      join public.academic_years y on y.id=e.academic_year_id
      where e.student_id=target_student_id and e.deleted_at is null
        and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(e.class_id,false))
    ) q),'[]'::jsonb),
    'guardians',coalesce((select jsonb_agg(to_jsonb(q) order by q.is_primary desc,lower(q.full_name)) from (
      select g.*,gl.auth_user_id,gl.can_view_reports,gl.can_receive_notifications,gl.verified_at
      from public.student_guardians g join public.guardian_links gl on gl.guardian_id=g.id
      where gl.student_id=target_student_id
    ) q),'[]'::jsonb),
    'reports',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc,q.sequence desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,t.name term_name,t.sequence,
        y.name academic_year_name,y.start_date,c.name class_name,
        round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id
      join public.classes c on c.id=e.class_id left join public.subject_results sr on sr.report_id=r.id
      where e.student_id=target_student_id and r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,t.id,y.id,c.id
    ) q),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.get_teacher_record(target_teacher_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.can_manage_teachers() and not exists(select 1 from public.teachers t where t.id=target_teacher_id and t.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  return (select jsonb_build_object('teacher',to_jsonb(t)||jsonb_build_object('full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'profile_email',au.email,'profile_name',p.full_name,'profile_role',case when p.id is null then null else public.current_app_role_for(p.role) end),'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb),'subjects',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb)) from public.teachers t left join public.profiles p on p.id=t.profile_id left join auth.users au on au.id=t.profile_id where t.id=target_teacher_id);
end$function$

CREATE OR REPLACE FUNCTION public.grade_for_mark(mark numeric, target_academic_year_id uuid, target_class_id uuid, target_subject_id uuid)
 RETURNS TABLE(grade text, remark text, grade_point numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select g.grade,g.remark,g.grade_point
  from public.grading_scales g
  where g.deleted_at is null and mark between g.min_mark and g.max_mark
    and (g.academic_year_id is null or g.academic_year_id=target_academic_year_id)
    and (g.class_id is null or g.class_id=target_class_id)
    and (g.subject_id is null or g.subject_id=target_subject_id)
  order by
    (g.subject_id is not null)::int desc,
    (g.class_id is not null)::int desc,
    (g.academic_year_id is not null)::int desc,
    g.display_order
  limit 1
$function$

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  requested_role text:=lower(coalesce(new.raw_app_meta_data->>'role',new.raw_user_meta_data->>'role',''));
  initial_role public.app_role;
  initial_active boolean:=true;
begin
  if not exists(select 1 from public.profiles) then
    initial_role:='system_admin'::public.app_role;
  elsif requested_role in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian') then
    initial_role:=requested_role::public.app_role;
  else
    initial_role:='parent_guardian'::public.app_role;
    initial_active:=false;
  end if;
  insert into public.profiles(id,full_name,role,active,mfa_required,phone)
  values(
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'),''),split_part(coalesce(new.email,''),'@',1),'User'),
    initial_role,
    initial_active,
    initial_role in ('system_admin','principal'),
    ''
  ) on conflict(id) do nothing;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.has_active_emergency_delegation(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean DEFAULT false, require_class_fields boolean DEFAULT false, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select cardinality(public.active_emergency_delegation_ids(
    target_class_id,target_subject_id,target_term_id,
    require_score_entry,require_class_fields,target_user_id
  ))>0
$function$

CREATE OR REPLACE FUNCTION public.has_any_active_emergency_delegation(target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1
    from public.emergency_academic_delegations d
    join public.profiles p on p.id=d.delegate_user_id and p.active
    where d.delegate_user_id=target_user_id
      and d.status='active'
      and now()>=d.valid_from
      and now()<d.valid_until
  )
$function$

CREATE OR REPLACE FUNCTION public.has_approved_report_correction(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.report_correction_requests r
    where r.report_id=target_report_id and r.status='approved'
      and r.reviewed_at>=now()-interval '180 days'
  )
$function$

CREATE OR REPLACE FUNCTION public.has_role(allowed text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(public.current_app_role()::text=any(allowed),false)
$function$

CREATE OR REPLACE FUNCTION public.health_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('health','summary');
 return jsonb_build_object('metrics',jsonb_build_object(
  'student_profiles',(select count(*) from public.health_student_profiles),
  'visits_today',(select count(*) from public.health_visits where visited_at::date=current_date and status<>'cancelled'),
  'open_observations',(select count(*) from public.health_visits where status in ('open','observation')),
  'referrals_30_days',(select count(*) from public.health_visits where disposition in ('referred','emergency_transfer') and visited_at>=now()-interval '30 days'),
  'immunizations_due',(select count(*) from public.health_immunizations where status in ('due','overdue') or (next_due_date is not null and next_due_date<=current_date))
 ));
end $function$

CREATE OR REPLACE FUNCTION public.health_my_children_emergency_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.student_name) from (
  select s.id student_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,p.blood_group,p.allergies,p.chronic_conditions,p.current_medications,p.dietary_restrictions,p.emergency_instructions,p.emergency_contact_name,p.emergency_contact_phone,p.emergency_contact_relation
  from public.guardian_links g join public.students s on s.id=g.student_id left join public.health_student_profiles p on p.student_id=s.id
  where g.auth_user_id=auth.uid() and g.can_view_reports and s.deleted_at is null
 )q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.health_record_medication(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('health','write');
 insert into public.health_medication_administrations(visit_id,student_id,medication_name,dosage,route,reason,administered_at,consent_reference,administered_by_hr_staff_id,created_by)
 values(nullif(payload->>'visit_id','')::uuid,(payload->>'student_id')::uuid,btrim(payload->>'medication_name'),btrim(payload->>'dosage'),nullif(payload->>'route',''),nullif(payload->>'reason',''),coalesce(nullif(payload->>'administered_at','')::timestamptz,now()),nullif(payload->>'consent_reference',''),nullif(payload->>'administered_by_hr_staff_id','')::uuid,auth.uid()) returning id into v_id;
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.health_save_immunization(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('health','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.health_immunizations(student_id,vaccine_name,dose_label,administered_date,next_due_date,provider,evidence_reference,status,notes,recorded_by) values((payload->>'student_id')::uuid,btrim(payload->>'vaccine_name'),nullif(payload->>'dose_label',''),nullif(payload->>'administered_date','')::date,nullif(payload->>'next_due_date','')::date,nullif(payload->>'provider',''),nullif(payload->>'evidence_reference',''),coalesce(nullif(payload->>'status',''),'recorded'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.health_immunizations set vaccine_name=coalesce(nullif(btrim(payload->>'vaccine_name'),''),vaccine_name),dose_label=case when payload ? 'dose_label' then nullif(payload->>'dose_label','') else dose_label end,administered_date=case when payload ? 'administered_date' then nullif(payload->>'administered_date','')::date else administered_date end,next_due_date=case when payload ? 'next_due_date' then nullif(payload->>'next_due_date','')::date else next_due_date end,provider=case when payload ? 'provider' then nullif(payload->>'provider','') else provider end,evidence_reference=case when payload ? 'evidence_reference' then nullif(payload->>'evidence_reference','') else evidence_reference end,status=coalesce(nullif(payload->>'status',''),status),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.health_save_profile(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;v_student uuid;
begin
 perform public.student_services_require_access('health','write');
 v_student:=(payload->>'student_id')::uuid;
 insert into public.health_student_profiles(student_id,blood_group,genotype,allergies,chronic_conditions,current_medications,dietary_restrictions,disability_or_support_notes,emergency_instructions,primary_doctor_name,primary_doctor_phone,insurance_provider,insurance_member_no,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,consent_notes,created_by,updated_by)
 values(v_student,nullif(payload->>'blood_group',''),nullif(payload->>'genotype',''),nullif(payload->>'allergies',''),nullif(payload->>'chronic_conditions',''),nullif(payload->>'current_medications',''),nullif(payload->>'dietary_restrictions',''),nullif(payload->>'disability_or_support_notes',''),nullif(payload->>'emergency_instructions',''),nullif(payload->>'primary_doctor_name',''),nullif(payload->>'primary_doctor_phone',''),nullif(payload->>'insurance_provider',''),nullif(payload->>'insurance_member_no',''),nullif(payload->>'emergency_contact_name',''),nullif(payload->>'emergency_contact_phone',''),nullif(payload->>'emergency_contact_relation',''),nullif(payload->>'consent_notes',''),auth.uid(),auth.uid())
 on conflict(student_id) do update set blood_group=excluded.blood_group,genotype=excluded.genotype,allergies=excluded.allergies,chronic_conditions=excluded.chronic_conditions,current_medications=excluded.current_medications,dietary_restrictions=excluded.dietary_restrictions,disability_or_support_notes=excluded.disability_or_support_notes,emergency_instructions=excluded.emergency_instructions,primary_doctor_name=excluded.primary_doctor_name,primary_doctor_phone=excluded.primary_doctor_phone,insurance_provider=excluded.insurance_provider,insurance_member_no=excluded.insurance_member_no,emergency_contact_name=excluded.emergency_contact_name,emergency_contact_phone=excluded.emergency_contact_phone,emergency_contact_relation=excluded.emergency_contact_relation,consent_notes=excluded.consent_notes,updated_by=auth.uid(),updated_at=now()
 returning id into v_id;
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.health_save_visit(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('health','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
  insert into public.health_visits(student_id,visited_at,complaint,observations,temperature_c,pulse_bpm,blood_pressure,treatment_notes,disposition,referral_destination,guardian_notified,guardian_notified_at,status,attended_by_hr_staff_id,created_by)
  values((payload->>'student_id')::uuid,coalesce(nullif(payload->>'visited_at','')::timestamptz,now()),btrim(payload->>'complaint'),nullif(payload->>'observations',''),nullif(payload->>'temperature_c','')::numeric,nullif(payload->>'pulse_bpm','')::integer,nullif(payload->>'blood_pressure',''),nullif(payload->>'treatment_notes',''),coalesce(nullif(payload->>'disposition',''),'returned_to_class'),nullif(payload->>'referral_destination',''),coalesce((payload->>'guardian_notified')::boolean,false),case when coalesce((payload->>'guardian_notified')::boolean,false) then now() end,coalesce(nullif(payload->>'status',''),'completed'),nullif(payload->>'attended_by_hr_staff_id','')::uuid,auth.uid()) returning id into v_id;
 else
  update public.health_visits set complaint=coalesce(nullif(btrim(payload->>'complaint'),''),complaint),observations=case when payload ? 'observations' then nullif(payload->>'observations','') else observations end,temperature_c=case when payload ? 'temperature_c' then nullif(payload->>'temperature_c','')::numeric else temperature_c end,pulse_bpm=case when payload ? 'pulse_bpm' then nullif(payload->>'pulse_bpm','')::integer else pulse_bpm end,blood_pressure=case when payload ? 'blood_pressure' then nullif(payload->>'blood_pressure','') else blood_pressure end,treatment_notes=case when payload ? 'treatment_notes' then nullif(payload->>'treatment_notes','') else treatment_notes end,disposition=coalesce(nullif(payload->>'disposition',''),disposition),referral_destination=case when payload ? 'referral_destination' then nullif(payload->>'referral_destination','') else referral_destination end,guardian_notified=coalesce((payload->>'guardian_notified')::boolean,guardian_notified),guardian_notified_at=case when coalesce((payload->>'guardian_notified')::boolean,false) and guardian_notified_at is null then now() else guardian_notified_at end,status=coalesce(nullif(payload->>'status',''),status),attended_by_hr_staff_id=case when payload ? 'attended_by_hr_staff_id' then nullif(payload->>'attended_by_hr_staff_id','')::uuid else attended_by_hr_staff_id end where id=v_id and status<>'cancelled';
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('health','clinic_visit_saved','health_visit',v_id,auth.uid(),'{}');
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.health_student_profile(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r jsonb;
begin
 perform public.student_services_require_access('health','read');
 select to_jsonb(q) into r from (
  select s.id student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,s.gender,s.date_of_birth,
   p.id profile_record_id,p.blood_group,p.genotype,p.allergies,p.chronic_conditions,p.current_medications,p.dietary_restrictions,p.disability_or_support_notes,p.emergency_instructions,p.primary_doctor_name,p.primary_doctor_phone,p.insurance_provider,p.insurance_member_no,p.emergency_contact_name,p.emergency_contact_phone,p.emergency_contact_relation,p.consent_notes,p.updated_at
  from public.students s left join public.health_student_profiles p on p.student_id=s.id where s.id=target_student_id and s.deleted_at is null
 )q;
 if r is null then raise exception 'Student not found'; end if;
 return r||jsonb_build_object(
  'recent_visits',coalesce((select jsonb_agg(to_jsonb(v) order by v.visited_at desc) from (select * from public.health_visits where student_id=target_student_id order by visited_at desc limit 25)v),'[]'::jsonb),
  'immunizations',coalesce((select jsonb_agg(to_jsonb(i) order by i.administered_date desc nulls last,i.created_at desc) from public.health_immunizations i where i.student_id=target_student_id),'[]'::jsonb)
 );
end $function$

CREATE OR REPLACE FUNCTION public.health_visit_register(search_text text DEFAULT NULL::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('health','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.visited_at desc) from (
  select v.id,v.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,v.visited_at,v.complaint,v.temperature_c,v.pulse_bpm,v.disposition,v.referral_destination,v.guardian_notified,v.status
  from public.health_visits v join public.students s on s.id=v.student_id
  where (date_from is null or v.visited_at::date>=date_from) and (date_to is null or v.visited_at::date<=date_to)
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,v.complaint,v.referral_destination) ilike '%'||search_text||'%')
  order by v.visited_at desc limit 300
 )q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.hostel_allocate_student(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;v_gender text;v_policy text;v_bed_status text;
begin
 perform public.student_services_require_access('hostel','write');
 select s.gender into v_gender from public.students s where s.id=(payload->>'student_id')::uuid and s.deleted_at is null and s.status='active';
 select h.gender_policy,b.status into v_policy,v_bed_status from public.hostel_beds b join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id where b.id=(payload->>'bed_id')::uuid and b.status<>'inactive' and r.active and h.active;
 if v_gender is null or v_policy is null then raise exception 'Student or bed unavailable'; end if;
 if v_bed_status not in ('available','occupied') then raise exception 'Bed is not available for allocation'; end if;
 if (v_policy='male' and v_gender<>'Male') or (v_policy='female' and v_gender<>'Female') then raise exception 'Student does not match house gender policy'; end if;
 if exists(select 1 from public.hostel_allocations where student_id=(payload->>'student_id')::uuid and status='active') then raise exception 'Student already has an active hostel allocation'; end if;
 if exists(select 1 from public.hostel_allocations where bed_id=(payload->>'bed_id')::uuid and status='active') then raise exception 'Bed is already occupied'; end if;
 insert into public.hostel_allocations(student_id,academic_year_id,bed_id,start_date,boarding_type,guardian_consent_reference,allocated_by) values((payload->>'student_id')::uuid,(payload->>'academic_year_id')::uuid,(payload->>'bed_id')::uuid,coalesce(nullif(payload->>'start_date','')::date,current_date),coalesce(nullif(payload->>'boarding_type',''),'full_boarding'),nullif(payload->>'guardian_consent_reference',''),auth.uid()) returning id into v_id;
 update public.hostel_beds set status='occupied' where id=(payload->>'bed_id')::uuid;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('hostel','student_allocated','hostel_allocation',v_id,auth.uid(),jsonb_build_object('student_id',payload->>'student_id','bed_id',payload->>'bed_id'));
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.hostel_allocation_register(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('hostel','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
  select a.id,a.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,a.academic_year_id,y.name academic_year,a.bed_id,b.bed_code,r.room_code,h.house_name,a.start_date,a.end_date,a.status,a.boarding_type,a.created_at
  from public.hostel_allocations a join public.students s on s.id=a.student_id join public.academic_years y on y.id=a.academic_year_id join public.hostel_beds b on b.id=a.bed_id join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id
  where (status_filter is null or a.status=status_filter) and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,h.house_name,r.room_code,b.bed_code) ilike '%'||search_text||'%')
 )q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.hostel_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('hostel','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'houses',(select count(*) from public.hostel_houses where active),
  'rooms',(select count(*) from public.hostel_rooms where active),
  'beds',(select count(*) from public.hostel_beds where status<>'inactive'),
  'occupied',(select count(*) from public.hostel_allocations where status='active'),
  'available',(select count(*) from public.hostel_beds b where b.status='available' and not exists(select 1 from public.hostel_allocations a where a.bed_id=b.id and a.status='active')),
  'students_out',(select count(distinct m.student_id) from public.hostel_movements m join public.hostel_allocations a on a.id=m.allocation_id where a.status='active' and m.movement_type in ('check_out','weekend_leave','temporary_exit') and not exists(select 1 from public.hostel_movements r where r.allocation_id=m.allocation_id and r.occurred_at>m.occurred_at and r.movement_type in ('check_in','return_from_leave','return'))),
  'open_incidents',(select count(*) from public.hostel_incidents where status in ('open','under_review','referred'))
 ));
end $function$

CREATE OR REPLACE FUNCTION public.hostel_end_allocation(target_allocation_id uuid, end_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_bed uuid;
begin
 perform public.student_services_require_access('hostel','write');
 select bed_id into v_bed from public.hostel_allocations where id=target_allocation_id and status='active' for update;
 if v_bed is null then raise exception 'Active allocation not found'; end if;
 update public.hostel_allocations set status='ended',end_date=current_date,ended_by=auth.uid(),updated_at=now() where id=target_allocation_id;
 update public.hostel_beds set status='available' where id=v_bed and status='occupied';
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('hostel','allocation_ended','hostel_allocation',target_allocation_id,auth.uid(),jsonb_build_object('reason',end_reason));
end $function$

CREATE OR REPLACE FUNCTION public.hostel_incident_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('hostel','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (select i.*,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name from public.hostel_incidents i join public.students s on s.id=i.student_id where status_filter is null or i.status=status_filter)q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.hostel_movement_register(target_allocation_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('hostel','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (select m.*,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name from public.hostel_movements m join public.students s on s.id=m.student_id where target_allocation_id is null or m.allocation_id=target_allocation_id order by m.occurred_at desc limit 300)q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.hostel_my_children_boarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.student_name) from (
  select a.id allocation_id,a.student_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,y.name academic_year,h.house_name,r.room_code,b.bed_code,a.boarding_type,a.start_date,
   (select jsonb_build_object('movement_type',m.movement_type,'occurred_at',m.occurred_at,'expected_return_at',m.expected_return_at,'destination',m.destination) from public.hostel_movements m where m.allocation_id=a.id order by m.occurred_at desc limit 1) latest_movement
  from public.guardian_links g join public.hostel_allocations a on a.student_id=g.student_id and a.status='active' join public.students s on s.id=a.student_id join public.academic_years y on y.id=a.academic_year_id join public.hostel_beds b on b.id=a.bed_id join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id
  where g.auth_user_id=auth.uid() and g.can_view_reports
 )q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.hostel_record_movement(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;v_student uuid;
begin
 perform public.student_services_require_access('hostel','write');
 select student_id into v_student from public.hostel_allocations where id=(payload->>'allocation_id')::uuid and status='active';
 if v_student is null then raise exception 'Active hostel allocation required'; end if;
 insert into public.hostel_movements(allocation_id,student_id,movement_type,occurred_at,expected_return_at,actual_return_at,destination,guardian_or_escort,guardian_contact,reason,recorded_by)
 values((payload->>'allocation_id')::uuid,v_student,payload->>'movement_type',coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),nullif(payload->>'expected_return_at','')::timestamptz,nullif(payload->>'actual_return_at','')::timestamptz,nullif(payload->>'destination',''),nullif(payload->>'guardian_or_escort',''),nullif(payload->>'guardian_contact',''),nullif(payload->>'reason',''),auth.uid()) returning id into v_id;
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.hostel_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('hostel','read');
 return jsonb_build_object(
  'houses',coalesce((select jsonb_agg(to_jsonb(q) order by q.house_name) from (select h.*,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) house_parent_name,(select count(*) from public.hostel_rooms r where r.house_id=h.id and r.active) room_count,(select count(*) from public.hostel_allocations a join public.hostel_beds b on b.id=a.bed_id join public.hostel_rooms r on r.id=b.room_id where r.house_id=h.id and a.status='active') occupied_count from public.hostel_houses h left join public.hr_staff_members s on s.id=h.house_parent_hr_staff_id)q),'[]'::jsonb),
  'rooms',coalesce((select jsonb_agg(to_jsonb(q) order by q.house_name,q.room_code) from (select r.*,h.house_name,(select count(*) from public.hostel_beds b where b.room_id=r.id) bed_count,(select count(*) from public.hostel_allocations a join public.hostel_beds b on b.id=a.bed_id where b.room_id=r.id and a.status='active') occupied_count from public.hostel_rooms r join public.hostel_houses h on h.id=r.house_id)q),'[]'::jsonb),
  'beds',coalesce((select jsonb_agg(to_jsonb(q) order by q.house_name,q.room_code,q.bed_code) from (select b.*,r.room_code,h.house_name,exists(select 1 from public.hostel_allocations a where a.bed_id=b.id and a.status='active') occupied from public.hostel_beds b join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id)q),'[]'::jsonb)
 );
end $function$

CREATE OR REPLACE FUNCTION public.hostel_resolve_incident(target_incident_id uuid, resolution_notes text, new_status text DEFAULT 'resolved'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('hostel','write');
 if $3 not in ('resolved','referred','cancelled') then raise exception 'Invalid hostel incident outcome'; end if;
 update public.hostel_incidents i set status=$3,resolution_notes=nullif($2,''),resolved_by=auth.uid(),resolved_at=case when $3 in ('resolved','cancelled') then now() else null end where i.id=$1 and i.status not in ('resolved','cancelled');
 if not found then raise exception 'Hostel incident is finalized or unavailable'; end if;
end $function$

CREATE OR REPLACE FUNCTION public.hostel_save_bed(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','configure');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.hostel_beds(room_id,bed_code,status,notes,created_by) values((payload->>'room_id')::uuid,upper(btrim(payload->>'bed_code')),coalesce(nullif(payload->>'status',''),'available'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.hostel_beds set status=coalesce(nullif(payload->>'status',''),status),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.hostel_save_house(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','configure');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.hostel_houses(house_code,house_name,gender_policy,capacity,house_parent_hr_staff_id,active,notes,created_by) values(upper(btrim(payload->>'house_code')),btrim(payload->>'house_name'),coalesce(nullif(payload->>'gender_policy',''),'mixed'),nullif(payload->>'capacity','')::integer,nullif(payload->>'house_parent_hr_staff_id','')::uuid,coalesce((payload->>'active')::boolean,true),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.hostel_houses set house_name=coalesce(nullif(btrim(payload->>'house_name'),''),house_name),gender_policy=coalesce(nullif(payload->>'gender_policy',''),gender_policy),capacity=case when payload ? 'capacity' then nullif(payload->>'capacity','')::integer else capacity end,house_parent_hr_staff_id=case when payload ? 'house_parent_hr_staff_id' then nullif(payload->>'house_parent_hr_staff_id','')::uuid else house_parent_hr_staff_id end,active=coalesce((payload->>'active')::boolean,active),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.hostel_save_incident(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','write');
 insert into public.hostel_incidents(allocation_id,student_id,occurred_at,incident_type,severity,summary,details,guardian_notified,guardian_notified_at,reported_by)
 values(nullif(payload->>'allocation_id','')::uuid,(payload->>'student_id')::uuid,coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),btrim(payload->>'incident_type'),coalesce(nullif(payload->>'severity',''),'medium'),btrim(payload->>'summary'),nullif(payload->>'details',''),coalesce((payload->>'guardian_notified')::boolean,false),case when coalesce((payload->>'guardian_notified')::boolean,false) then now() end,auth.uid()) returning id into v_id;
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.hostel_save_room(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','configure');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.hostel_rooms(house_id,room_code,room_name,floor_label,capacity,active,notes,created_by) values((payload->>'house_id')::uuid,upper(btrim(payload->>'room_code')),nullif(payload->>'room_name',''),nullif(payload->>'floor_label',''),(payload->>'capacity')::integer,coalesce((payload->>'active')::boolean,true),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.hostel_rooms set room_name=case when payload ? 'room_name' then nullif(payload->>'room_name','') else room_name end,floor_label=case when payload ? 'floor_label' then nullif(payload->>'floor_label','') else floor_label end,capacity=coalesce(nullif(payload->>'capacity','')::integer,capacity),active=coalesce((payload->>'active')::boolean,active),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.hr_block_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if current_setting('app.hr_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'HR history cannot be hard deleted; use lifecycle status or cancellation instead' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.hr_cancel_leave(target_request_id uuid, cancellation_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.hr_leave_requests;
begin
  perform public.hr_require_access(true,array['system_admin']);
  update public.hr_leave_requests set status='cancelled',decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(cancellation_reason),'') where id=target_request_id and status in ('pending','approved') returning * into v_row;
  if v_row.id is null then raise exception 'Leave request cannot be cancelled'; end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.hr_decide_leave(target_request_id uuid, decision text, decision_reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.hr_leave_requests; v_role text;
begin
  v_role:=public.hr_require_access(true,array['system_admin','principal']);
  if decision not in ('approved','rejected') then raise exception 'Leave decision must be approved or rejected'; end if;
  update public.hr_leave_requests set status=decision,decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(decision_reason_text),'') where id=target_request_id and status='pending' returning * into v_row;
  if v_row.id is null then raise exception 'Pending leave request not found'; end if;
  insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by) values(v_row.staff_id,'leave_'||decision,current_date,jsonb_build_object('leave_request_id',v_row.id,'start_date',v_row.start_date,'end_date',v_row.end_date,'decided_by_role',v_role,'reason',decision_reason_text),auth.uid());
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.hr_generate_staff_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  root text;
  n bigint;
  candidate text;
begin
  select coalesce(nullif(regexp_replace(upper(identifier_root),'[^A-Z0-9]','','g'),''), nullif(regexp_replace(upper(school_name),'[^A-Z]','','g'),''), 'SCH')
    into root from public.school_settings limit 1;
  root:=left(root,8);
  loop
    n:=nextval('public.hr_staff_no_seq');
    candidate:=root||lpad(n::text,6,'0');
    exit when not exists(select 1 from public.hr_staff_members where staff_no=candidate)
      and not exists(select 1 from public.teachers where staff_no::text=candidate)
      and not exists(select 1 from public.headteachers where staff_no::text=candidate)
      and not exists(select 1 from public.accounts_office_staff where staff_no::text=candidate);
  end loop;
  return candidate;
end $function$

CREATE OR REPLACE FUNCTION public.hr_leave_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.hr_require_access(false,array['system_admin','principal']);
  return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'staff_id',l.staff_id,'staff_no',s.staff_no,'staff_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,''))),'department',s.department,'job_title',s.job_title,'leave_type',l.leave_type,'start_date',l.start_date,'end_date',l.end_date,'days',l.days,'reason',l.reason,'status',l.status,'submitted_at',l.submitted_at,'decided_at',l.decided_at,'decision_reason',l.decision_reason) order by case when l.status='pending' then 0 else 1 end,l.start_date desc) from public.hr_leave_requests l join public.hr_staff_members s on s.id=l.staff_id where s.deleted_at is null and (coalesce(nullif(status_filter,''),'')='' or l.status=status_filter)),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.hr_my_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Access unavailable' using errcode='42501'; end if;
  select id into v_id from public.hr_staff_members where profile_id=auth.uid() and deleted_at is null and active;
  if v_id is null then return null; end if;
  return jsonb_build_object('staff',(select to_jsonb(s)||jsonb_build_object('full_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,'')))) from public.hr_staff_members s where s.id=v_id),'qualifications',coalesce((select jsonb_agg(to_jsonb(q) order by q.awarded_on desc nulls last) from public.hr_staff_qualifications q where q.staff_id=v_id),'[]'::jsonb),'leave',coalesce((select jsonb_agg(to_jsonb(l) order by l.start_date desc) from public.hr_leave_requests l where l.staff_id=v_id),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.hr_record_staff_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='INSERT' then
    insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by)
    values(new.id,'staff_created',coalesce(new.date_joined,current_date),jsonb_build_object('employment_status',new.employment_status,'source_type',new.source_type),coalesce(auth.uid(),new.created_by));
  elsif tg_op='UPDATE' then
    if old.employment_status is distinct from new.employment_status then
      insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by)
      values(new.id,'employment_status_changed',current_date,jsonb_build_object('from',old.employment_status,'to',new.employment_status),auth.uid());
    end if;
    if old.job_title is distinct from new.job_title or old.department is distinct from new.department then
      insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by)
      values(new.id,'assignment_changed',current_date,jsonb_build_object('job_title_from',old.job_title,'job_title_to',new.job_title,'department_from',old.department,'department_to',new.department),auth.uid());
    end if;
  end if;
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.hr_require_access(require_write boolean DEFAULT false, allowed_roles text[] DEFAULT ARRAY['system_admin'::text, 'principal'::text])
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_role text;
  v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_role:=public.current_app_role()::text;
  if v_role is null or not (v_role=any(allowed_roles)) then raise exception 'HR access is not allowed for this role' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'HR access is unavailable while the school licence is locked' using errcode='42501'; end if;
  if require_write and not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'HR changes are unavailable while the school licence is read-only' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for Staff & HR' using errcode='42501'; end if;
  return v_role;
end $function$

CREATE OR REPLACE FUNCTION public.hr_save_document(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_staff uuid; v_row public.hr_staff_documents;
begin
  perform public.hr_require_access(true,array['system_admin']);
  v_id:=nullif(payload->>'id','')::uuid; v_staff:=nullif(payload->>'staff_id','')::uuid;
  if v_staff is null then raise exception 'Staff member is required'; end if;
  if v_id is null then
    insert into public.hr_staff_documents(staff_id,document_type,title,reference_no,issued_on,expires_on,storage_path,verification_status,notes,created_by)
    values(v_staff,coalesce(nullif(btrim(payload->>'document_type'),''),'other'),coalesce(nullif(btrim(payload->>'title'),''),'Document'),nullif(btrim(payload->>'reference_no'),''),nullif(payload->>'issued_on','')::date,nullif(payload->>'expires_on','')::date,nullif(btrim(payload->>'storage_path'),''),coalesce(nullif(payload->>'verification_status',''),'unverified'),nullif(btrim(payload->>'notes'),''),auth.uid()) returning * into v_row;
  else
    update public.hr_staff_documents set document_type=coalesce(nullif(btrim(payload->>'document_type'),''),document_type),title=coalesce(nullif(btrim(payload->>'title'),''),title),reference_no=case when payload?'reference_no' then nullif(btrim(payload->>'reference_no'),'') else reference_no end,issued_on=case when payload?'issued_on' then nullif(payload->>'issued_on','')::date else issued_on end,expires_on=case when payload?'expires_on' then nullif(payload->>'expires_on','')::date else expires_on end,storage_path=case when payload?'storage_path' then nullif(btrim(payload->>'storage_path'),'') else storage_path end,verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then auth.uid() else verified_by end,verified_at=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then now() else verified_at end,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end where id=v_id and staff_id=v_staff returning * into v_row;
  end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.hr_save_qualification(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_staff uuid; v_row public.hr_staff_qualifications;
begin
  perform public.hr_require_access(true,array['system_admin']);
  v_id:=nullif(payload->>'id','')::uuid; v_staff:=nullif(payload->>'staff_id','')::uuid;
  if v_staff is null then raise exception 'Staff member is required'; end if;
  if v_id is null then
    insert into public.hr_staff_qualifications(staff_id,qualification,institution,field_of_study,awarded_on,expires_on,verification_status,notes,created_by)
    values(v_staff,coalesce(nullif(btrim(payload->>'qualification'),''),'Qualification'),nullif(btrim(payload->>'institution'),''),nullif(btrim(payload->>'field_of_study'),''),nullif(payload->>'awarded_on','')::date,nullif(payload->>'expires_on','')::date,coalesce(nullif(payload->>'verification_status',''),'unverified'),nullif(btrim(payload->>'notes'),''),auth.uid()) returning * into v_row;
  else
    update public.hr_staff_qualifications set qualification=coalesce(nullif(btrim(payload->>'qualification'),''),qualification),institution=case when payload?'institution' then nullif(btrim(payload->>'institution'),'') else institution end,field_of_study=case when payload?'field_of_study' then nullif(btrim(payload->>'field_of_study'),'') else field_of_study end,awarded_on=case when payload?'awarded_on' then nullif(payload->>'awarded_on','')::date else awarded_on end,expires_on=case when payload?'expires_on' then nullif(payload->>'expires_on','')::date else expires_on end,verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then auth.uid() else verified_by end,verified_at=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then now() else verified_at end,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end where id=v_id and staff_id=v_staff returning * into v_row;
  end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.hr_save_staff(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_id uuid;
  v_row public.hr_staff_members;
  v_staff_no text;
begin
  perform public.hr_require_access(true,array['system_admin']);
  v_id:=nullif(payload->>'id','')::uuid;
  if v_id is null then
    v_staff_no:=coalesce(nullif(btrim(payload->>'staff_no'),''),public.hr_generate_staff_no());
    insert into public.hr_staff_members(source_type,staff_no,first_name,middle_name,last_name,gender,date_of_birth,email,phone,address,department,job_title,employment_type,employment_status,date_joined,date_ended,qualification,specialization,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,notes,active,created_by)
    values('other',v_staff_no,coalesce(nullif(btrim(payload->>'first_name'),''),'Staff'),nullif(btrim(payload->>'middle_name'),''),coalesce(nullif(btrim(payload->>'last_name'),''),''),nullif(payload->>'gender',''),nullif(payload->>'date_of_birth','')::date,nullif(btrim(payload->>'email'),''),nullif(btrim(payload->>'phone'),''),nullif(btrim(payload->>'address'),''),nullif(btrim(payload->>'department'),''),nullif(btrim(payload->>'job_title'),''),coalesce(nullif(payload->>'employment_type',''),'permanent'),coalesce(nullif(payload->>'employment_status',''),'active'),nullif(payload->>'date_joined','')::date,nullif(payload->>'date_ended','')::date,nullif(btrim(payload->>'qualification'),''),nullif(btrim(payload->>'specialization'),''),nullif(btrim(payload->>'emergency_contact_name'),''),nullif(btrim(payload->>'emergency_contact_phone'),''),nullif(btrim(payload->>'emergency_contact_relation'),''),nullif(btrim(payload->>'notes'),''),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into v_row;
  else
    update public.hr_staff_members s set
      department=coalesce(nullif(btrim(payload->>'department'),''),s.department), job_title=coalesce(nullif(btrim(payload->>'job_title'),''),s.job_title),
      employment_type=coalesce(nullif(payload->>'employment_type',''),s.employment_type), employment_status=coalesce(nullif(payload->>'employment_status',''),s.employment_status),
      date_joined=coalesce(nullif(payload->>'date_joined','')::date,s.date_joined), date_ended=nullif(payload->>'date_ended','')::date,
      emergency_contact_name=coalesce(nullif(btrim(payload->>'emergency_contact_name'),''),s.emergency_contact_name), emergency_contact_phone=coalesce(nullif(btrim(payload->>'emergency_contact_phone'),''),s.emergency_contact_phone), emergency_contact_relation=coalesce(nullif(btrim(payload->>'emergency_contact_relation'),''),s.emergency_contact_relation),
      notes=case when payload ? 'notes' then nullif(btrim(payload->>'notes'),'') else s.notes end,
      active=coalesce((payload->>'active')::boolean,s.active),
      first_name=case when s.source_type='other' and payload ? 'first_name' then coalesce(nullif(btrim(payload->>'first_name'),''),s.first_name) else s.first_name end,
      middle_name=case when s.source_type='other' and payload ? 'middle_name' then nullif(btrim(payload->>'middle_name'),'') else s.middle_name end,
      last_name=case when s.source_type='other' and payload ? 'last_name' then coalesce(nullif(btrim(payload->>'last_name'),''),s.last_name) else s.last_name end,
      email=case when s.source_type='other' and payload ? 'email' then nullif(btrim(payload->>'email'),'') else s.email end,
      phone=case when s.source_type='other' and payload ? 'phone' then nullif(btrim(payload->>'phone'),'') else s.phone end,
      address=case when s.source_type='other' and payload ? 'address' then nullif(btrim(payload->>'address'),'') else s.address end,
      gender=case when s.source_type='other' and payload ? 'gender' then nullif(payload->>'gender','') else s.gender end,
      date_of_birth=case when s.source_type='other' and payload ? 'date_of_birth' then nullif(payload->>'date_of_birth','')::date else s.date_of_birth end,
      qualification=case when payload ? 'qualification' then nullif(btrim(payload->>'qualification'),'') else s.qualification end,
      specialization=case when payload ? 'specialization' then nullif(btrim(payload->>'specialization'),'') else s.specialization end
    where s.id=v_id and s.deleted_at is null returning * into v_row;
    if v_row.id is null then raise exception 'Staff member not found'; end if;
  end if;
  return to_jsonb(v_row)||jsonb_build_object('full_name',btrim(concat_ws(' ',v_row.first_name,nullif(v_row.middle_name,''),nullif(v_row.last_name,''))));
end $function$

CREATE OR REPLACE FUNCTION public.hr_staff_detail(target_staff_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_staff jsonb;
begin
  perform public.hr_require_access(false,array['system_admin','principal']);
  select to_jsonb(s)||jsonb_build_object('full_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,'')))) into v_staff from public.hr_staff_members s where s.id=target_staff_id and s.deleted_at is null;
  if v_staff is null then raise exception 'Staff member not found'; end if;
  return jsonb_build_object(
    'staff',v_staff,
    'qualifications',coalesce((select jsonb_agg(to_jsonb(q) order by q.awarded_on desc nulls last,q.created_at desc) from public.hr_staff_qualifications q where q.staff_id=target_staff_id),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.expires_on nulls last,d.created_at desc) from public.hr_staff_documents d where d.staff_id=target_staff_id),'[]'::jsonb),
    'leave',coalesce((select jsonb_agg(to_jsonb(l) order by l.start_date desc,l.created_at desc) from public.hr_leave_requests l where l.staff_id=target_staff_id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.event_date desc,e.created_at desc) from public.hr_employment_events e where e.staff_id=target_staff_id),'[]'::jsonb),
    'payroll',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'payroll_number',p.payroll_number::text,'active',p.active,'salary_grade_id',p.salary_grade_id,'basic_salary_override',p.basic_salary_override)) from public.finance_payroll_profiles p where p.hr_staff_member_id=target_staff_id),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.hr_staff_directory(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text, department_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_role text;
begin
  v_role:=public.hr_require_access(false,array['system_admin','principal']);
  return jsonb_build_object(
    'role',v_role,
    'metrics',jsonb_build_object(
      'total',(select count(*) from public.hr_staff_members where deleted_at is null),
      'active',(select count(*) from public.hr_staff_members where deleted_at is null and active and employment_status in ('active','probation','leave')),
      'teachers',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='teacher'),
      'leadership',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='principal'),
      'accounts_office',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='accounts_office'),
      'other',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='other'),
      'pending_leave',(select count(*) from public.hr_leave_requests where status='pending')
    ),
    'rows',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'profile_id',s.profile_id,'source_type',s.source_type,'staff_no',s.staff_no,
      'full_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,''))),
      'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,'gender',s.gender,'email',s.email,'phone',s.phone,
      'department',s.department,'job_title',s.job_title,'employment_type',s.employment_type,'employment_status',s.employment_status,
      'date_joined',s.date_joined,'active',s.active,'payroll_linked',exists(select 1 from public.finance_payroll_profiles p where p.hr_staff_member_id=s.id)
    ) order by s.active desc,s.last_name,s.first_name)
    from public.hr_staff_members s where s.deleted_at is null
      and (coalesce(nullif(search_text,''),'')='' or s.staff_no ilike '%'||search_text||'%' or s.first_name ilike '%'||search_text||'%' or s.last_name ilike '%'||search_text||'%' or coalesce(s.email,'') ilike '%'||search_text||'%')
      and (coalesce(nullif(status_filter,''),'')='' or s.employment_status=status_filter)
      and (coalesce(nullif(department_filter,''),'')='' or coalesce(s.department,'')=department_filter)
    ),'[]'::jsonb),
    'departments',coalesce((select jsonb_agg(x.department order by x.department) from (select distinct department from public.hr_staff_members where deleted_at is null and coalesce(department,'')<>'') x),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.hr_submit_leave_for_staff(target_staff_id uuid, leave_kind text, start_on date, end_on date, reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.hr_leave_requests; v_days numeric;
begin
  perform public.hr_require_access(true,array['system_admin']);
  if end_on<start_on then raise exception 'Leave end date cannot be before start date'; end if;
  v_days:=(end_on-start_on)+1;
  insert into public.hr_leave_requests(staff_id,leave_type,start_date,end_date,days,reason,status,submitted_by)
  values(target_staff_id,leave_kind,start_on,end_on,v_days,reason_text,'pending',auth.uid()) returning * into v_row;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.hr_submit_my_leave(leave_kind text, start_on date, end_on date, reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_staff uuid; v_license jsonb; v_row public.hr_leave_requests; v_days numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Leave requests are unavailable while the school licence is read-only' using errcode='42501'; end if;
  select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and deleted_at is null and active;
  if v_staff is null then raise exception 'Active staff record not found' using errcode='42501'; end if;
  if end_on<start_on then raise exception 'Leave end date cannot be before start date'; end if;
  v_days:=(end_on-start_on)+1;
  insert into public.hr_leave_requests(staff_id,leave_type,start_date,end_date,days,reason,status,submitted_by) values(v_staff,leave_kind,start_on,end_on,v_days,reason_text,'pending',auth.uid()) returning * into v_row;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.hr_sync_staff_from_source()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_type text;
  v_source_id uuid;
  v_profile_id uuid;
  v_staff_no text;
  v_first text;
  v_middle text;
  v_last text;
  v_gender text;
  v_dob date;
  v_email text;
  v_phone text;
  v_address text;
  v_department text;
  v_job text;
  v_status text;
  v_joined date;
  v_qualification text;
  v_specialization text;
  v_active boolean;
  v_deleted timestamptz;
begin
  if tg_op='DELETE' then
    v_type:=case tg_table_name when 'teachers' then 'teacher' when 'headteachers' then 'principal' when 'accounts_office_staff' then 'accounts_office' else null end;
    if v_type is not null then
      update public.hr_staff_members
      set active=false, employment_status='inactive', deleted_at=coalesce(deleted_at,now()), updated_at=now()
      where source_type=v_type and source_id=old.id;
    end if;
    return old;
  end if;

  if tg_table_name='teachers' then
    v_type:='teacher'; v_source_id:=new.id; v_profile_id:=new.profile_id; v_staff_no:=new.staff_no::text;
    v_first:=new.first_name; v_middle:=new.middle_name; v_last:=new.last_name; v_gender:=new.gender; v_dob:=new.date_of_birth;
    v_email:=new.email::text; v_phone:=new.phone; v_address:=new.address; v_department:='Academic'; v_job:='Teacher';
    v_status:=coalesce(new.employment_status,'active'); v_joined:=new.date_joined; v_qualification:=new.qualification; v_specialization:=new.specialization;
    v_active:=coalesce(new.active,true); v_deleted:=new.deleted_at;
  elsif tg_table_name='headteachers' then
    v_type:='principal'; v_source_id:=new.id; v_profile_id:=new.profile_id; v_staff_no:=new.staff_no::text;
    v_first:=new.first_name; v_middle:=new.middle_name; v_last:=new.last_name; v_gender:=new.gender; v_dob:=null;
    v_email:=new.email::text; v_phone:=new.phone; v_address:=new.address; v_department:='Leadership'; v_job:='Principal';
    v_status:=coalesce(new.employment_status,'active'); v_joined:=new.date_appointed; v_qualification:=new.qualification; v_specialization:=null;
    v_active:=coalesce(new.active,true); v_deleted:=new.deleted_at;
  elsif tg_table_name='accounts_office_staff' then
    v_type:='accounts_office'; v_source_id:=new.id; v_profile_id:=new.profile_id; v_staff_no:=new.staff_no::text;
    v_first:=coalesce(nullif(new.full_name,''),'Accounts Office Staff'); v_middle:=null; v_last:=''; v_gender:=null; v_dob:=null;
    v_email:=new.email::text; v_phone:=new.phone; v_address:=new.contact_address; v_department:='Finance'; v_job:=coalesce(new.job_title,'Accounts Office Staff');
    v_status:=case when coalesce(new.active,true) then 'active' else 'inactive' end; v_joined:=null; v_qualification:=null; v_specialization:=null;
    v_active:=coalesce(new.active,true); v_deleted:=new.deleted_at;
  else
    return new;
  end if;

  if coalesce(v_staff_no,'')='' then v_staff_no:=public.hr_generate_staff_no(); end if;

  insert into public.hr_staff_members(
    profile_id,source_type,source_id,staff_no,first_name,middle_name,last_name,gender,date_of_birth,email,phone,address,
    department,job_title,employment_status,date_joined,qualification,specialization,active,deleted_at,created_by
  ) values(
    v_profile_id,v_type,v_source_id,v_staff_no,coalesce(v_first,'Staff'),v_middle,coalesce(v_last,''),v_gender,v_dob,v_email,v_phone,v_address,
    v_department,v_job,
    case when v_status in ('active','probation','leave','suspended','resigned','terminated','retired','inactive') then v_status else case when v_active then 'active' else 'inactive' end end,
    v_joined,v_qualification,v_specialization,v_active,v_deleted,auth.uid()
  )
  on conflict (source_type,source_id) do update set
    profile_id=excluded.profile_id,
    staff_no=excluded.staff_no,
    first_name=excluded.first_name,
    middle_name=excluded.middle_name,
    last_name=excluded.last_name,
    gender=excluded.gender,
    date_of_birth=coalesce(excluded.date_of_birth,public.hr_staff_members.date_of_birth),
    email=excluded.email,
    phone=excluded.phone,
    address=excluded.address,
    department=coalesce(nullif(public.hr_staff_members.department,''),excluded.department),
    job_title=coalesce(nullif(public.hr_staff_members.job_title,''),excluded.job_title),
    employment_status=excluded.employment_status,
    date_joined=coalesce(public.hr_staff_members.date_joined,excluded.date_joined),
    qualification=coalesce(excluded.qualification,public.hr_staff_members.qualification),
    specialization=coalesce(excluded.specialization,public.hr_staff_members.specialization),
    active=excluded.active,
    deleted_at=excluded.deleted_at,
    updated_at=now();

  return new;
end $function$

CREATE OR REPLACE FUNCTION public.hr_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin new.updated_at:=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.id_card_effective_status(target_status text, target_expires_on date)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$ select case when target_status='active' and target_expires_on<current_date then 'expired' else target_status end $function$

CREATE OR REPLACE FUNCTION public.id_card_photo_path_is_referenced(target_student_id uuid, target_photo_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare clean_path text:=btrim(coalesce(target_photo_path,'')); begin if auth.uid() is null or not public.can_manage_student(target_student_id) then return true;end if; if target_student_id is null or clean_path='' then return true;end if; return exists(select 1 from public.student_id_cards where student_id=target_student_id and snapshot#>>'{student,photo_url}'=clean_path); end$function$

CREATE OR REPLACE FUNCTION public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare result integer:=0;clean_path text:=btrim(coalesce(target_photo_path,'')); begin if auth.uid() is null or not public.can_manage_student(target_student_id) then raise exception 'Access denied' using errcode='42501';end if; if clean_path='' then return 0;end if; select count(*)::integer into result from public.student_id_cards where student_id=target_student_id and snapshot#>>'{student,photo_url}'=clean_path; return coalesce(result,0); end$function$

CREATE OR REPLACE FUNCTION public.id_card_principal_signature_path_is_referenced(target_signature_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select auth.uid() is not null and (public.is_system_admin() or public.current_app_role()='principal') and btrim(coalesce(target_signature_path,''))<>'' and (
  exists(select 1 from public.student_id_cards c where c.snapshot#>>'{principal,signature_path}'=target_signature_path)
  or exists(select 1 from public.staff_id_cards c where c.snapshot#>>'{principal,signature_path}'=target_signature_path)
 )
$function$

CREATE OR REPLACE FUNCTION public.institution_academic_model()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select jsonb_build_object(
    'institution_type',coalesce(s.institution_type,'basic_jhs'),
    'academic_period_model',coalesce(s.academic_period_model,'term')
  )
  from public.school_settings s
  order by s.created_at
  limit 1
$function$

CREATE OR REPLACE FUNCTION public.inventory_access_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_role text; v_staff_role text; v_staff_id uuid; v_profile uuid:=auth.uid();
begin
  if v_profile is null then return jsonb_build_object('authorized',false); end if;
  v_role:=public.current_app_role()::text;
  select a.access_role,a.staff_id into v_staff_role,v_staff_id
  from public.inventory_staff_access a
  join public.hr_staff_members h on h.id=a.staff_id and h.active and h.deleted_at is null
  where a.profile_id=v_profile and a.active and a.revoked_at is null
  order by a.appointed_at desc limit 1;
  return jsonb_build_object(
    'authorized', v_role in ('system_admin','principal') or v_staff_role is not null,
    'app_role',v_role,'inventory_role',v_staff_role,'staff_id',v_staff_id,
    'view', v_role in ('system_admin','principal') or v_staff_role is not null,
    'catalog', v_role='system_admin' or v_staff_role in ('inventory_manager','storekeeper'),
    'stock', v_role='system_admin' or v_staff_role in ('inventory_manager','storekeeper'),
    'procurement', v_role='system_admin' or v_staff_role in ('inventory_manager','procurement_officer'),
    'receive', v_role='system_admin' or v_staff_role in ('inventory_manager','procurement_officer','storekeeper'),
    'approve', v_role in ('system_admin','principal') or v_staff_role='inventory_manager',
    'assets', v_role='system_admin' or v_staff_role in ('inventory_manager','asset_officer'),
    'staff_access', v_role='system_admin',
    'settings', v_role='system_admin'
  );
end $function$

CREATE OR REPLACE FUNCTION public.inventory_adjust_stock(target_item_id uuid, target_location_id uuid, quantity_change numeric, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin perform public.inventory_require_access('stock',true); if coalesce(btrim(reason_text),'')='' then raise exception 'Adjustment reason is required'; end if; v_id:=public.inventory_record_stock_movement(target_item_id,target_location_id,case when quantity_change>0 then 'adjust_in' else 'adjust_out' end,quantity_change,null,'manual_adjustment',null,null,null,null,reason_text,reason_text); return jsonb_build_object('movement_id',v_id,'balance',public.inventory_current_stock(target_item_id,target_location_id)); end $function$

CREATE OR REPLACE FUNCTION public.inventory_asset_assignment_register(active_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.inventory_require_access('view',false);
  return coalesce((select jsonb_agg(jsonb_build_object('id',aa.id,'asset_id',aa.asset_id,'asset_tag',a.asset_tag,'asset_name',a.asset_name,'staff_id',aa.staff_id,'staff_no',h.staff_no,'staff_name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),'assigned_location_id',aa.assigned_location_id,'location_name',l.name,'assigned_on',aa.assigned_on,'due_on',aa.due_on,'purpose',aa.purpose,'assignment_condition',aa.assignment_condition,'returned_at',aa.returned_at,'return_condition',aa.return_condition,'return_notes',aa.return_notes) order by (aa.returned_at is null) desc,aa.assigned_on desc,aa.created_at desc)
    from public.inventory_asset_assignments aa
    join public.inventory_assets a on a.id=aa.asset_id
    join public.hr_staff_members h on h.id=aa.staff_id
    left join public.inventory_locations l on l.id=aa.assigned_location_id
    where (not active_only or aa.returned_at is null)),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_asset_maintenance_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.inventory_require_access('view',false);
  return coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'asset_id',m.asset_id,'asset_tag',a.asset_tag,'asset_name',a.asset_name,'maintenance_type',m.maintenance_type,'opened_on',m.opened_on,'completed_on',m.completed_on,'vendor_id',m.vendor_id,'vendor_name',s.supplier_name,'cost',m.cost,'description',m.description,'outcome',m.outcome,'next_due_on',m.next_due_on,'status',m.status) order by case m.status when 'open' then 0 else 1 end,m.opened_on desc,m.created_at desc)
    from public.inventory_asset_maintenance m join public.inventory_assets a on a.id=m.asset_id left join public.inventory_suppliers s on s.id=m.vendor_id
    where coalesce(nullif(status_filter,''),'')='' or m.status=status_filter),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_asset_writeoff_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.inventory_require_access('view',false);
  return coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'writeoff_no',w.writeoff_no,'asset_id',w.asset_id,'asset_tag',a.asset_tag,'asset_name',a.asset_name,'reason',w.reason,'status',w.status,'requested_at',w.requested_at,'decided_at',w.decided_at,'decision_reason',w.decision_reason) order by case w.status when 'pending' then 0 else 1 end,w.requested_at desc)
    from public.inventory_asset_writeoffs w join public.inventory_assets a on a.id=w.asset_id
    where coalesce(nullif(status_filter,''),'')='' or w.status=status_filter),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_assets_register(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text, location_filter uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('view',false); return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'asset_tag',a.asset_tag,'asset_name',a.asset_name,'item_id',a.item_id,'category',a.category,'serial_number',a.serial_number,'model',a.model,'manufacturer',a.manufacturer,'supplier_id',a.supplier_id,'supplier_name',s.supplier_name,'purchase_date',a.purchase_date,'purchase_cost',a.purchase_cost,'warranty_expires_on',a.warranty_expires_on,'current_location_id',a.current_location_id,'location_name',l.name,'asset_status',a.asset_status,'asset_condition',a.asset_condition,'next_maintenance_on',a.next_maintenance_on,'active',a.active,'assigned_to',case when aa.id is null then null else btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))) end,'assigned_staff_id',aa.staff_id) order by a.active desc,a.asset_name,a.asset_tag) from public.inventory_assets a left join public.inventory_suppliers s on s.id=a.supplier_id left join public.inventory_locations l on l.id=a.current_location_id left join public.inventory_asset_assignments aa on aa.asset_id=a.id and aa.returned_at is null left join public.hr_staff_members h on h.id=aa.staff_id where (coalesce(nullif(search_text,''),'')='' or a.asset_tag ilike '%'||search_text||'%' or a.asset_name ilike '%'||search_text||'%' or coalesce(a.serial_number,'') ilike '%'||search_text||'%') and (coalesce(nullif(status_filter,''),'')='' or a.asset_status=status_filter) and (location_filter is null or a.current_location_id=location_filter)),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_assign_asset(target_asset_id uuid, target_staff_id uuid, target_location_id uuid DEFAULT NULL::uuid, due_date_value date DEFAULT NULL::date, purpose_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_assignment public.inventory_asset_assignments;
begin perform public.inventory_require_access('assets',true); if not exists(select 1 from public.hr_staff_members where id=target_staff_id and active and deleted_at is null) then raise exception 'Active staff member not found'; end if; perform pg_advisory_xact_lock(hashtextextended(target_asset_id::text,0)); if not exists(select 1 from public.inventory_assets where id=target_asset_id and active and asset_status='available') then raise exception 'Asset is not available for assignment'; end if; insert into public.inventory_asset_assignments(asset_id,staff_id,assigned_location_id,due_on,purpose,assignment_condition,assigned_by) select a.id,target_staff_id,target_location_id,due_date_value,purpose_text,a.asset_condition,auth.uid() from public.inventory_assets a where a.id=target_asset_id returning * into v_assignment; update public.inventory_assets set asset_status='assigned',current_location_id=coalesce(target_location_id,current_location_id) where id=target_asset_id; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_assigned','asset',target_asset_id,jsonb_build_object('staff_id',target_staff_id,'assignment_id',v_assignment.id,'due_on',due_date_value),auth.uid()); return to_jsonb(v_assignment); end $function$

CREATE OR REPLACE FUNCTION public.inventory_block_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if current_setting('app.inventory_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'Inventory and asset history cannot be hard deleted; use lifecycle status instead' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.inventory_catalog(search_text text DEFAULT NULL::text, item_type_filter text DEFAULT NULL::text, category_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.inventory_require_access('view',false);
  return coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'item_code',i.item_code,'item_name',i.item_name,'item_type',i.item_type,'category',i.category,'unit_of_measure',i.unit_of_measure,'description',i.description,'reorder_level',i.reorder_level,'reorder_quantity',i.reorder_quantity,'estimated_unit_cost',i.estimated_unit_cost,'preferred_supplier_id',i.preferred_supplier_id,'preferred_supplier',s.supplier_name,'active',i.active,'total_stock',case when i.item_type='consumable' then (select coalesce(sum(m.quantity_delta),0) from public.inventory_stock_movements m where m.item_id=i.id and m.voided_at is null) else null end) order by i.active desc,i.item_name) from public.inventory_items i left join public.inventory_suppliers s on s.id=i.preferred_supplier_id where (coalesce(nullif(search_text,''),'')='' or i.item_code ilike '%'||search_text||'%' or i.item_name ilike '%'||search_text||'%' or coalesce(i.category,'') ilike '%'||search_text||'%') and (coalesce(nullif(item_type_filter,''),'')='' or i.item_type=item_type_filter) and (coalesce(nullif(category_filter,''),'')='' or coalesce(i.category,'')=category_filter)),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_complete_asset_maintenance(target_maintenance_id uuid, outcome_text text, next_due_date date DEFAULT NULL::date, cost_value numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_asset_maintenance;
begin perform public.inventory_require_access('assets',true); update public.inventory_asset_maintenance set completed_on=current_date,outcome=coalesce(nullif(btrim(outcome_text),''),'Completed'),next_due_on=next_due_date,cost=coalesce(cost_value,cost),status='completed',completed_by=auth.uid() where id=target_maintenance_id and status='open' returning * into v_row; if v_row.id is null then raise exception 'Open maintenance record not found'; end if; update public.inventory_assets set asset_status='available',next_maintenance_on=coalesce(next_due_date,next_maintenance_on) where id=v_row.asset_id and asset_status='maintenance'; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_maintenance_completed','asset',v_row.asset_id,jsonb_build_object('maintenance_id',v_row.id,'next_due_on',next_due_date),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_create_purchase_order(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_request uuid; v_supplier uuid; v_po public.inventory_purchase_orders; v_line public.inventory_purchase_request_lines; v_price jsonb; v_unit numeric; v_count int:=0;
begin
  perform public.inventory_require_access('procurement',true);
  v_request:=nullif(payload->>'request_id','')::uuid; v_supplier:=nullif(payload->>'supplier_id','')::uuid;
  if not exists(select 1 from public.inventory_purchase_requests where id=v_request and status='approved') then raise exception 'Approved purchase request not found'; end if;
  if not exists(select 1 from public.inventory_suppliers where id=v_supplier and active) then raise exception 'Active supplier not found'; end if;
  if exists(select 1 from public.inventory_purchase_orders where request_id=v_request and status not in ('rejected','cancelled')) then raise exception 'An active purchase order already exists for this request'; end if;
  insert into public.inventory_purchase_orders(po_no,request_id,supplier_id,order_date,expected_date,status,notes,created_by)
  values(public.inventory_generate_procurement_no('po'),v_request,v_supplier,coalesce(nullif(payload->>'order_date','')::date,current_date),nullif(payload->>'expected_date','')::date,'draft',nullif(btrim(payload->>'notes'),''),auth.uid()) returning * into v_po;
  for v_line in select * from public.inventory_purchase_request_lines where request_id=v_request order by created_at loop
    v_price:=null;
    if jsonb_typeof(payload->'pricing')='array' then select value into v_price from jsonb_array_elements(payload->'pricing') where value->>'request_line_id'=v_line.id::text limit 1; end if;
    v_unit:=coalesce(nullif(v_price->>'unit_cost','')::numeric,v_line.estimated_unit_cost,(select estimated_unit_cost from public.inventory_items where id=v_line.item_id),0);
    insert into public.inventory_purchase_order_lines(purchase_order_id,request_line_id,item_id,quantity_ordered,unit_cost,notes) values(v_po.id,v_line.id,v_line.item_id,v_line.quantity,v_unit,v_line.notes);
    v_count:=v_count+1;
  end loop;
  insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('purchase_order_created','purchase_order',v_po.id,jsonb_build_object('po_no',v_po.po_no,'request_id',v_request,'supplier_id',v_supplier,'line_count',v_count),auth.uid());
  return public.inventory_purchase_order_detail(v_po.id);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_create_purchase_request(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_request public.inventory_purchase_requests; v_line jsonb; v_count int:=0;
begin
  perform public.inventory_require_access('procurement',true);
  if coalesce(btrim(payload->>'justification'),'')='' then raise exception 'Purchase justification is required'; end if;
  if jsonb_typeof(payload->'lines')<>'array' then raise exception 'Purchase request lines are required'; end if;
  insert into public.inventory_purchase_requests(request_no,justification,needed_by,status,requested_by)
  values(public.inventory_generate_procurement_no('pr'),btrim(payload->>'justification'),nullif(payload->>'needed_by','')::date,'submitted',auth.uid()) returning * into v_request;
  for v_line in select value from jsonb_array_elements(payload->'lines') loop
    if nullif(v_line->>'item_id','') is null or coalesce(nullif(v_line->>'quantity','')::numeric,0)<=0 then raise exception 'Each purchase line requires an item and positive quantity'; end if;
    if not exists(select 1 from public.inventory_items where id=(v_line->>'item_id')::uuid and active) then raise exception 'Purchase request contains an inactive or missing item'; end if;
    insert into public.inventory_purchase_request_lines(request_id,item_id,quantity,estimated_unit_cost,notes)
    values(v_request.id,(v_line->>'item_id')::uuid,(v_line->>'quantity')::numeric,nullif(v_line->>'estimated_unit_cost','')::numeric,nullif(btrim(v_line->>'notes'),''));
    v_count:=v_count+1;
  end loop;
  if v_count=0 then raise exception 'Purchase request must contain at least one line'; end if;
  insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('purchase_request_submitted','purchase_request',v_request.id,jsonb_build_object('request_no',v_request.request_no,'line_count',v_count),auth.uid());
  return public.inventory_purchase_request_detail(v_request.id);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_current_stock(target_item_id uuid, target_location_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(sum(quantity_delta),0)::numeric from public.inventory_stock_movements where item_id=target_item_id and location_id=target_location_id and voided_at is null
$function$

CREATE OR REPLACE FUNCTION public.inventory_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb;
begin v_access:=public.inventory_require_access('view',false); return jsonb_build_object('access',v_access,'metrics',jsonb_build_object('active_items',(select count(*) from public.inventory_items where active),'consumables',(select count(*) from public.inventory_items where active and item_type='consumable'),'assets',(select count(*) from public.inventory_assets where active),'assigned_assets',(select count(*) from public.inventory_assets where active and asset_status='assigned'),'maintenance_assets',(select count(*) from public.inventory_assets where active and asset_status='maintenance'),'pending_item_requests',(select count(*) from public.inventory_item_requests where status='pending'),'pending_writeoffs',(select count(*) from public.inventory_asset_writeoffs where status='pending'),'purchase_requests_pending',(select count(*) from public.inventory_purchase_requests where status='submitted'),'purchase_orders_pending',(select count(*) from public.inventory_purchase_orders where status='draft'),'purchase_orders_open',(select count(*) from public.inventory_purchase_orders where status in ('approved','partially_received')),'goods_receipts',(select count(*) from public.inventory_goods_receipts),'low_stock_items',(select count(*) from public.inventory_items i where i.active and i.item_type='consumable' and (select coalesce(sum(m.quantity_delta),0) from public.inventory_stock_movements m where m.item_id=i.id and m.voided_at is null)<=i.reorder_level)),'recent_events',coalesce((select jsonb_agg(to_jsonb(e) order by e.occurred_at desc) from (select * from public.inventory_events order by occurred_at desc limit 20)e),'[]'::jsonb)); end $function$

CREATE OR REPLACE FUNCTION public.inventory_decide_asset_writeoff(target_writeoff_id uuid, decision text, decision_reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_asset_writeoffs;
begin perform public.inventory_require_access('approve',true); if decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if; update public.inventory_asset_writeoffs set status=decision,decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(decision_reason_text),'') where id=target_writeoff_id and status='pending' returning * into v_row; if v_row.id is null then raise exception 'Pending write-off request not found'; end if; if decision='approved' then update public.inventory_assets set asset_status='disposed',active=false,disposed_on=current_date where id=v_row.asset_id and active; end if; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_writeoff_'||decision,'asset',v_row.asset_id,jsonb_build_object('writeoff_id',v_row.id,'writeoff_no',v_row.writeoff_no,'reason',decision_reason_text),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_decide_item_request(target_request_id uuid, decision text, decision_reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_item_requests;
begin perform public.inventory_require_access('stock',true); if decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if; update public.inventory_item_requests set status=decision,decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(decision_reason_text),'') where id=target_request_id and status='pending' returning * into v_row; if v_row.id is null then raise exception 'Pending item request not found'; end if; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('item_request_'||decision,'item_request',v_row.id,jsonb_build_object('request_no',v_row.request_no,'reason',decision_reason_text),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_decide_purchase_order(target_po_id uuid, decision text, decision_reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_po public.inventory_purchase_orders;
begin perform public.inventory_require_access('approve',true); if decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if; update public.inventory_purchase_orders set status=decision,approved_by=auth.uid(),approved_at=now(),decision_reason=nullif(btrim(decision_reason_text),'') where id=target_po_id and status='draft' returning * into v_po; if v_po.id is null then raise exception 'Draft purchase order not found'; end if; if decision='approved' then update public.inventory_purchase_requests set status='converted',updated_at=now() where id=v_po.request_id and status='approved'; end if; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('purchase_order_'||decision,'purchase_order',v_po.id,jsonb_build_object('po_no',v_po.po_no,'reason',decision_reason_text),auth.uid()); return public.inventory_purchase_order_detail(v_po.id); end $function$

CREATE OR REPLACE FUNCTION public.inventory_decide_purchase_request(target_request_id uuid, decision text, decision_reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_purchase_requests;
begin perform public.inventory_require_access('approve',true); if decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if; update public.inventory_purchase_requests set status=decision,decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(decision_reason_text),'') where id=target_request_id and status='submitted' returning * into v_row; if v_row.id is null then raise exception 'Submitted purchase request not found'; end if; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('purchase_request_'||decision,'purchase_request',v_row.id,jsonb_build_object('request_no',v_row.request_no,'reason',decision_reason_text),auth.uid()); return public.inventory_purchase_request_detail(v_row.id); end $function$

CREATE OR REPLACE FUNCTION public.inventory_fulfill_item_request(target_request_id uuid, target_location_id uuid, notes_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_item_requests; v_movement uuid;
begin perform public.inventory_require_access('stock',true); select * into v_row from public.inventory_item_requests where id=target_request_id and status='approved' for update; if v_row.id is null then raise exception 'Approved item request not found'; end if; v_movement:=public.inventory_record_stock_movement(v_row.item_id,target_location_id,'issue',-v_row.quantity,null,'item_request',v_row.id,v_row.request_no,null,v_row.staff_id,v_row.purpose,notes_text); update public.inventory_item_requests set status='fulfilled',fulfilled_movement_id=v_movement,fulfilled_by=auth.uid(),fulfilled_at=now() where id=v_row.id returning * into v_row; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('item_request_fulfilled','item_request',v_row.id,jsonb_build_object('request_no',v_row.request_no,'movement_id',v_movement,'location_id',target_location_id),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_generate_code(code_kind text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_root text:=public.inventory_identifier_root(); v_n bigint;
begin
  if code_kind='supplier' then v_n:=nextval('public.inventory_supplier_code_seq'); return v_root||'-SUP-'||lpad(v_n::text,5,'0');
  elsif code_kind='item' then v_n:=nextval('public.inventory_item_code_seq'); return v_root||'-ITM-'||lpad(v_n::text,6,'0');
  elsif code_kind='asset' then v_n:=nextval('public.inventory_asset_tag_seq'); return v_root||'-AST-'||lpad(v_n::text,6,'0');
  elsif code_kind='request' then v_n:=nextval('public.inventory_request_no_seq'); return v_root||'-REQ-'||to_char(current_date,'YYYY')||'-'||lpad(v_n::text,6,'0');
  elsif code_kind='writeoff' then v_n:=nextval('public.inventory_writeoff_no_seq'); return v_root||'-WOF-'||to_char(current_date,'YYYY')||'-'||lpad(v_n::text,6,'0');
  else raise exception 'Unknown inventory code kind'; end if;
end $function$

CREATE OR REPLACE FUNCTION public.inventory_generate_procurement_no(code_kind text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_root text:=public.inventory_identifier_root(); v_n bigint;
begin
  if code_kind='pr' then v_n:=nextval('public.inventory_pr_no_seq'); return v_root||'-PR-'||to_char(current_date,'YYYY')||'-'||lpad(v_n::text,6,'0');
  elsif code_kind='po' then v_n:=nextval('public.inventory_po_no_seq'); return v_root||'-PO-'||to_char(current_date,'YYYY')||'-'||lpad(v_n::text,6,'0');
  elsif code_kind='grn' then v_n:=nextval('public.inventory_grn_no_seq'); return v_root||'-GRN-'||to_char(current_date,'YYYY')||'-'||lpad(v_n::text,6,'0');
  else raise exception 'Unknown procurement number kind'; end if;
end $function$

CREATE OR REPLACE FUNCTION public.inventory_goods_receipt_detail(target_grn_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_header jsonb;
begin perform public.inventory_require_access('view',false); select jsonb_build_object('id',g.id,'grn_no',g.grn_no,'purchase_order_id',g.purchase_order_id,'po_no',po.po_no,'supplier_id',po.supplier_id,'supplier_name',s.supplier_name,'supplier_delivery_ref',g.supplier_delivery_ref,'received_on',g.received_on,'received_by',g.received_by,'notes',g.notes) into v_header from public.inventory_goods_receipts g join public.inventory_purchase_orders po on po.id=g.purchase_order_id join public.inventory_suppliers s on s.id=po.supplier_id where g.id=target_grn_id; if v_header is null then raise exception 'Goods receipt not found'; end if; return jsonb_build_object('header',v_header,'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'purchase_order_line_id',l.purchase_order_line_id,'item_id',l.item_id,'item_code',i.item_code,'item_name',i.item_name,'item_type',i.item_type,'quantity_received',l.quantity_received,'unit_of_measure',i.unit_of_measure,'unit_cost',l.unit_cost,'line_total',l.quantity_received*l.unit_cost,'location_id',l.location_id,'location_name',loc.name,'stock_movement_id',l.stock_movement_id,'asset_ids',to_jsonb(l.asset_ids),'notes',l.notes) order by i.item_name) from public.inventory_goods_receipt_lines l join public.inventory_items i on i.id=l.item_id left join public.inventory_locations loc on loc.id=l.location_id where l.goods_receipt_id=target_grn_id),'[]'::jsonb)); end $function$

CREATE OR REPLACE FUNCTION public.inventory_goods_receipt_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('view',false); return coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'grn_no',g.grn_no,'purchase_order_id',g.purchase_order_id,'po_no',po.po_no,'supplier_name',s.supplier_name,'supplier_delivery_ref',g.supplier_delivery_ref,'received_on',g.received_on,'total',coalesce((select sum(l.quantity_received*l.unit_cost) from public.inventory_goods_receipt_lines l where l.goods_receipt_id=g.id),0)) order by g.received_on desc,g.created_at desc) from public.inventory_goods_receipts g join public.inventory_purchase_orders po on po.id=g.purchase_order_id join public.inventory_suppliers s on s.id=po.supplier_id),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_identifier_root()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_root text;
begin
  select coalesce(nullif(regexp_replace(upper(identifier_root),'[^A-Z0-9]','','g'),''),nullif(regexp_replace(upper(school_name),'[^A-Z]','','g'),''),'SCH') into v_root from public.school_settings limit 1;
  return left(coalesce(v_root,'SCH'),8);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_issue_stock(target_item_id uuid, target_location_id uuid, quantity numeric, recipient_staff_uuid uuid DEFAULT NULL::uuid, purpose_text text DEFAULT NULL::text, notes_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin perform public.inventory_require_access('stock',true); if quantity<=0 then raise exception 'Issue quantity must be positive'; end if; if recipient_staff_uuid is not null and not exists(select 1 from public.hr_staff_members where id=recipient_staff_uuid and active and deleted_at is null) then raise exception 'Active staff recipient not found'; end if; v_id:=public.inventory_record_stock_movement(target_item_id,target_location_id,'issue',-quantity,null,'manual_issue',null,null,null,recipient_staff_uuid,purpose_text,notes_text); return jsonb_build_object('movement_id',v_id,'balance',public.inventory_current_stock(target_item_id,target_location_id)); end $function$

CREATE OR REPLACE FUNCTION public.inventory_item_request_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('stock',false); return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'request_no',r.request_no,'staff_id',r.staff_id,'staff_no',h.staff_no,'staff_name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),'department',h.department,'item_id',r.item_id,'item_code',i.item_code,'item_name',i.item_name,'quantity',r.quantity,'unit_of_measure',i.unit_of_measure,'purpose',r.purpose,'preferred_location_id',r.preferred_location_id,'preferred_location',l.name,'status',r.status,'requested_at',r.requested_at,'decision_reason',r.decision_reason,'fulfilled_at',r.fulfilled_at) order by case r.status when 'pending' then 0 when 'approved' then 1 else 2 end,r.requested_at desc) from public.inventory_item_requests r join public.hr_staff_members h on h.id=r.staff_id join public.inventory_items i on i.id=r.item_id left join public.inventory_locations l on l.id=r.preferred_location_id where coalesce(nullif(status_filter,''),'')='' or r.status=status_filter),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_locations_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ begin perform public.inventory_require_access('view',false); return coalesce((select jsonb_agg(to_jsonb(l) order by l.active desc,l.name) from public.inventory_locations l),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_my_account()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_staff uuid; v_license jsonb;
begin if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if; v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Inventory access unavailable' using errcode='42501'; end if; select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and active and deleted_at is null; if v_staff is null then return null; end if; return jsonb_build_object('staff_id',v_staff,'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'request_no',r.request_no,'item_name',i.item_name,'quantity',r.quantity,'unit_of_measure',i.unit_of_measure,'purpose',r.purpose,'status',r.status,'requested_at',r.requested_at,'decision_reason',r.decision_reason,'fulfilled_at',r.fulfilled_at) order by r.requested_at desc) from public.inventory_item_requests r join public.inventory_items i on i.id=r.item_id where r.staff_id=v_staff),'[]'::jsonb),'assets',coalesce((select jsonb_agg(jsonb_build_object('assignment_id',aa.id,'asset_id',a.id,'asset_tag',a.asset_tag,'asset_name',a.asset_name,'asset_condition',a.asset_condition,'assigned_on',aa.assigned_on,'due_on',aa.due_on,'purpose',aa.purpose,'location',l.name) order by aa.assigned_on desc) from public.inventory_asset_assignments aa join public.inventory_assets a on a.id=aa.asset_id left join public.inventory_locations l on l.id=aa.assigned_location_id where aa.staff_id=v_staff and aa.returned_at is null),'[]'::jsonb),'recent_issues',coalesce((select jsonb_agg(jsonb_build_object('movement_id',m.id,'item_name',i.item_name,'quantity',abs(m.quantity_delta),'unit_of_measure',i.unit_of_measure,'purpose',m.purpose,'posted_at',m.posted_at,'location',l.name) order by m.posted_at desc) from (select * from public.inventory_stock_movements where recipient_staff_id=v_staff and movement_type='issue' and voided_at is null order by posted_at desc limit 30)m join public.inventory_items i on i.id=m.item_id join public.inventory_locations l on l.id=m.location_id),'[]'::jsonb)); end $function$

CREATE OR REPLACE FUNCTION public.inventory_my_request_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_license jsonb; v_staff uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Inventory access unavailable' using errcode='42501'; end if;
  select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and active and deleted_at is null limit 1;
  if v_staff is null then raise exception 'Active staff record not found' using errcode='42501'; end if;
  return jsonb_build_object(
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'item_code',i.item_code,'item_name',i.item_name,'category',i.category,'unit_of_measure',i.unit_of_measure) order by i.item_name) from public.inventory_items i where i.active and i.item_type='consumable'),'[]'::jsonb),
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'code',l.code,'name',l.name) order by l.name) from public.inventory_locations l where l.active),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.inventory_purchase_order_detail(target_po_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_header jsonb;
begin
  perform public.inventory_require_access('view',false);
  select jsonb_build_object('id',po.id,'po_no',po.po_no,'request_id',po.request_id,'request_no',r.request_no,'supplier_id',po.supplier_id,'supplier_name',s.supplier_name,'order_date',po.order_date,'expected_date',po.expected_date,'status',po.status,'notes',po.notes,'created_by',po.created_by,'approved_by',po.approved_by,'approved_at',po.approved_at,'decision_reason',po.decision_reason,'total',coalesce((select sum(l.quantity_ordered*l.unit_cost) from public.inventory_purchase_order_lines l where l.purchase_order_id=po.id),0),'received_total',coalesce((select sum(l.quantity_received*l.unit_cost) from public.inventory_purchase_order_lines l where l.purchase_order_id=po.id),0)) into v_header from public.inventory_purchase_orders po join public.inventory_purchase_requests r on r.id=po.request_id join public.inventory_suppliers s on s.id=po.supplier_id where po.id=target_po_id;
  if v_header is null then raise exception 'Purchase order not found'; end if;
  return jsonb_build_object('header',v_header,'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'request_line_id',l.request_line_id,'item_id',l.item_id,'item_code',i.item_code,'item_name',i.item_name,'item_type',i.item_type,'unit_of_measure',i.unit_of_measure,'quantity_ordered',l.quantity_ordered,'quantity_received',l.quantity_received,'quantity_outstanding',l.quantity_ordered-l.quantity_received,'unit_cost',l.unit_cost,'line_total',l.quantity_ordered*l.unit_cost,'notes',l.notes) order by i.item_name) from public.inventory_purchase_order_lines l join public.inventory_items i on i.id=l.item_id where l.purchase_order_id=target_po_id),'[]'::jsonb),'receipts',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'grn_no',g.grn_no,'supplier_delivery_ref',g.supplier_delivery_ref,'received_on',g.received_on,'received_by',g.received_by,'notes',g.notes) order by g.received_on desc,g.created_at desc) from public.inventory_goods_receipts g where g.purchase_order_id=target_po_id),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.inventory_purchase_order_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('view',false); return coalesce((select jsonb_agg(jsonb_build_object('id',po.id,'po_no',po.po_no,'request_id',po.request_id,'request_no',r.request_no,'supplier_id',po.supplier_id,'supplier_name',s.supplier_name,'order_date',po.order_date,'expected_date',po.expected_date,'status',po.status,'total',coalesce((select sum(l.quantity_ordered*l.unit_cost) from public.inventory_purchase_order_lines l where l.purchase_order_id=po.id),0),'received_total',coalesce((select sum(l.quantity_received*l.unit_cost) from public.inventory_purchase_order_lines l where l.purchase_order_id=po.id),0),'decision_reason',po.decision_reason) order by case po.status when 'draft' then 0 when 'approved' then 1 when 'partially_received' then 2 else 3 end,po.order_date desc,po.created_at desc) from public.inventory_purchase_orders po join public.inventory_purchase_requests r on r.id=po.request_id join public.inventory_suppliers s on s.id=po.supplier_id where coalesce(nullif(status_filter,''),'')='' or po.status=status_filter),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_purchase_request_detail(target_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_header jsonb;
begin
  v_access:=public.inventory_require_access('view',false);
  select jsonb_build_object('id',r.id,'request_no',r.request_no,'justification',r.justification,'needed_by',r.needed_by,'status',r.status,'requested_by',r.requested_by,'requested_at',r.requested_at,'decided_by',r.decided_by,'decided_at',r.decided_at,'decision_reason',r.decision_reason,'requester_name',p.full_name,'estimated_total',coalesce((select sum(l.quantity*coalesce(l.estimated_unit_cost,0)) from public.inventory_purchase_request_lines l where l.request_id=r.id),0)) into v_header from public.inventory_purchase_requests r left join public.profiles p on p.id=r.requested_by where r.id=target_request_id;
  if v_header is null then raise exception 'Purchase request not found'; end if;
  return jsonb_build_object('header',v_header,'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'item_id',l.item_id,'item_code',i.item_code,'item_name',i.item_name,'item_type',i.item_type,'unit_of_measure',i.unit_of_measure,'quantity',l.quantity,'estimated_unit_cost',l.estimated_unit_cost,'estimated_line_total',l.quantity*coalesce(l.estimated_unit_cost,0),'notes',l.notes) order by i.item_name) from public.inventory_purchase_request_lines l join public.inventory_items i on i.id=l.item_id where l.request_id=target_request_id),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.inventory_purchase_request_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('view',false); return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'request_no',r.request_no,'justification',r.justification,'needed_by',r.needed_by,'status',r.status,'requested_at',r.requested_at,'requester_name',p.full_name,'line_count',(select count(*) from public.inventory_purchase_request_lines l where l.request_id=r.id),'estimated_total',coalesce((select sum(l.quantity*coalesce(l.estimated_unit_cost,0)) from public.inventory_purchase_request_lines l where l.request_id=r.id),0),'decision_reason',r.decision_reason) order by case r.status when 'submitted' then 0 when 'approved' then 1 else 2 end,r.requested_at desc) from public.inventory_purchase_requests r left join public.profiles p on p.id=r.requested_by where coalesce(nullif(status_filter,''),'')='' or r.status=status_filter),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_receive_purchase_order(target_po_id uuid, supplier_delivery_ref_text text, receipt_lines jsonb, notes_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_po public.inventory_purchase_orders; v_grn public.inventory_goods_receipts; v_line jsonb; v_pol public.inventory_purchase_order_lines; v_item public.inventory_items; v_qty numeric; v_location uuid; v_movement uuid; v_assets uuid[]; v_asset_id uuid; v_serials jsonb; v_serial text; v_i int; v_all_received boolean;
begin
  perform public.inventory_require_access('receive',true);
  if jsonb_typeof(receipt_lines)<>'array' or jsonb_array_length(receipt_lines)=0 then raise exception 'Receipt lines are required'; end if;
  select * into v_po from public.inventory_purchase_orders where id=target_po_id and status in ('approved','partially_received') for update;
  if v_po.id is null then raise exception 'Approved or partially received purchase order not found'; end if;
  insert into public.inventory_goods_receipts(grn_no,purchase_order_id,supplier_delivery_ref,notes,received_by) values(public.inventory_generate_procurement_no('grn'),v_po.id,nullif(btrim(supplier_delivery_ref_text),''),nullif(btrim(notes_text),''),auth.uid()) returning * into v_grn;
  for v_line in select value from jsonb_array_elements(receipt_lines) loop
    select * into v_pol from public.inventory_purchase_order_lines where id=nullif(v_line->>'purchase_order_line_id','')::uuid and purchase_order_id=v_po.id for update;
    if v_pol.id is null then raise exception 'Purchase order line not found'; end if;
    v_qty:=coalesce(nullif(v_line->>'quantity_received','')::numeric,0); if v_qty<=0 then raise exception 'Received quantity must be positive'; end if;
    if v_pol.quantity_received+v_qty>v_pol.quantity_ordered then raise exception 'Receipt quantity exceeds outstanding order quantity'; end if;
    select * into v_item from public.inventory_items where id=v_pol.item_id and active; if v_item.id is null then raise exception 'Active inventory item not found for purchase order line'; end if;
    v_location:=nullif(v_line->>'location_id','')::uuid; if v_location is null or not exists(select 1 from public.inventory_locations where id=v_location and active) then raise exception 'Active receiving location is required'; end if;
    v_movement:=null; v_assets:='{}'::uuid[];
    if v_item.item_type='consumable' then
      v_movement:=public.inventory_record_stock_movement(v_item.id,v_location,'receipt',v_qty,v_pol.unit_cost,'goods_receipt',v_grn.id,v_grn.grn_no,null,null,'Purchase order receipt',nullif(btrim(v_line->>'notes'),''));
    else
      if trunc(v_qty)<>v_qty then raise exception 'Asset receipt quantity must be a whole number'; end if;
      v_serials:=case when jsonb_typeof(v_line->'serial_numbers')='array' then v_line->'serial_numbers' else '[]'::jsonb end;
      for v_i in 1..v_qty::int loop
        v_serial:=nullif(btrim(coalesce(v_serials->>(v_i-1),'')),'');
        insert into public.inventory_assets(asset_tag,item_id,asset_name,category,serial_number,supplier_id,purchase_date,purchase_cost,current_location_id,asset_status,asset_condition,active,purchase_order_line_id,created_by)
        values(public.inventory_generate_code('asset'),v_item.id,v_item.item_name,v_item.category,v_serial,v_po.supplier_id,current_date,v_pol.unit_cost,v_location,'available','new',true,v_pol.id,auth.uid()) returning id into v_asset_id;
        v_assets:=array_append(v_assets,v_asset_id);
        insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_received','asset',v_asset_id,jsonb_build_object('grn_no',v_grn.grn_no,'po_no',v_po.po_no,'purchase_order_line_id',v_pol.id),auth.uid());
      end loop;
    end if;
    insert into public.inventory_goods_receipt_lines(goods_receipt_id,purchase_order_line_id,item_id,location_id,quantity_received,unit_cost,stock_movement_id,asset_ids,notes)
    values(v_grn.id,v_pol.id,v_item.id,v_location,v_qty,v_pol.unit_cost,v_movement,v_assets,nullif(btrim(v_line->>'notes'),''));
    update public.inventory_purchase_order_lines set quantity_received=quantity_received+v_qty,updated_at=now() where id=v_pol.id;
  end loop;
  select bool_and(quantity_received>=quantity_ordered) into v_all_received from public.inventory_purchase_order_lines where purchase_order_id=v_po.id;
  update public.inventory_purchase_orders set status=case when coalesce(v_all_received,false) then 'received' else 'partially_received' end,updated_at=now() where id=v_po.id returning * into v_po;
  insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('goods_received','goods_receipt',v_grn.id,jsonb_build_object('grn_no',v_grn.grn_no,'po_no',v_po.po_no,'po_status',v_po.status),auth.uid());
  return public.inventory_goods_receipt_detail(v_grn.id);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_record_asset_maintenance(target_asset_id uuid, maintenance_kind text, description_text text, vendor_uuid uuid DEFAULT NULL::uuid, cost_value numeric DEFAULT NULL::numeric, next_due_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_asset_maintenance;
begin perform public.inventory_require_access('assets',true); if exists(select 1 from public.inventory_asset_assignments where asset_id=target_asset_id and returned_at is null) then raise exception 'Assigned asset must be returned before maintenance'; end if; if not exists(select 1 from public.inventory_assets where id=target_asset_id and active and asset_status not in ('disposed','lost')) then raise exception 'Asset is not eligible for maintenance'; end if; insert into public.inventory_asset_maintenance(asset_id,maintenance_type,vendor_id,cost,description,next_due_on,status,created_by) values(target_asset_id,maintenance_kind,vendor_uuid,cost_value,coalesce(nullif(btrim(description_text),''),'Maintenance'),next_due_date,'open',auth.uid()) returning * into v_row; update public.inventory_assets set asset_status='maintenance' where id=target_asset_id; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_maintenance_opened','asset',target_asset_id,jsonb_build_object('maintenance_id',v_row.id,'type',maintenance_kind),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_record_stock_movement(target_item_id uuid, target_location_id uuid, movement_kind text, quantity_change numeric, unit_cost_value numeric DEFAULT NULL::numeric, reference_kind text DEFAULT NULL::text, reference_uuid uuid DEFAULT NULL::uuid, reference_text text DEFAULT NULL::text, related_movement_uuid uuid DEFAULT NULL::uuid, recipient_staff_uuid uuid DEFAULT NULL::uuid, purpose_text text DEFAULT NULL::text, notes_text text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_type text; v_balance numeric; v_id uuid;
begin
  select item_type into v_type from public.inventory_items where id=target_item_id and active;
  if v_type is null then raise exception 'Active inventory item not found'; end if;
  if v_type<>'consumable' then raise exception 'Stock movements apply only to consumable items'; end if;
  if not exists(select 1 from public.inventory_locations where id=target_location_id and active) then raise exception 'Active inventory location not found'; end if;
  if quantity_change=0 then raise exception 'Stock movement quantity cannot be zero'; end if;
  if movement_kind in ('opening','receipt','return','adjust_in','transfer_in') and quantity_change<0 then raise exception 'Positive stock movement expected'; end if;
  if movement_kind in ('issue','adjust_out','transfer_out') and quantity_change>0 then raise exception 'Negative stock movement expected'; end if;
  if quantity_change<0 then
    perform pg_advisory_xact_lock(hashtextextended(target_item_id::text||':'||target_location_id::text,0));
    v_balance:=public.inventory_current_stock(target_item_id,target_location_id);
    if v_balance+quantity_change<0 then raise exception 'Insufficient stock: available %, requested %',v_balance,abs(quantity_change); end if;
  end if;
  insert into public.inventory_stock_movements(item_id,location_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,reference_no,related_movement_id,recipient_staff_id,purpose,notes,posted_by)
  values(target_item_id,target_location_id,movement_kind,quantity_change,unit_cost_value,reference_kind,reference_uuid,reference_text,related_movement_uuid,recipient_staff_uuid,purpose_text,notes_text,auth.uid()) returning id into v_id;
  insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('stock_'||movement_kind,'stock_movement',v_id,jsonb_build_object('item_id',target_item_id,'location_id',target_location_id,'quantity_delta',quantity_change,'reference_no',reference_text),auth.uid());
  return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.inventory_request_asset_writeoff(target_asset_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_asset_writeoffs;
begin perform public.inventory_require_access('assets',true); if coalesce(btrim(reason_text),'')='' then raise exception 'Write-off reason is required'; end if; if exists(select 1 from public.inventory_asset_assignments where asset_id=target_asset_id and returned_at is null) then raise exception 'Assigned asset cannot be written off'; end if; if not exists(select 1 from public.inventory_assets where id=target_asset_id and active and asset_status<>'disposed') then raise exception 'Active asset not found'; end if; insert into public.inventory_asset_writeoffs(writeoff_no,asset_id,reason,requested_by) values(public.inventory_generate_code('writeoff'),target_asset_id,reason_text,auth.uid()) returning * into v_row; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_writeoff_requested','asset',target_asset_id,jsonb_build_object('writeoff_id',v_row.id,'writeoff_no',v_row.writeoff_no),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_require_access(capability text DEFAULT 'view'::text, require_write boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_access:=public.inventory_access_snapshot();
  if not coalesce((v_access->>capability)::boolean,false) then raise exception 'Inventory access is not allowed for this operation' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Inventory access is unavailable while the school licence is locked' using errcode='42501'; end if;
  if require_write and not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Inventory changes are unavailable while the school licence is read-only' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for Inventory management' using errcode='42501'; end if;
  return v_access;
end $function$

CREATE OR REPLACE FUNCTION public.inventory_return_asset(target_assignment_id uuid, return_condition_value text DEFAULT NULL::text, return_notes_text text DEFAULT NULL::text, target_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_assignment public.inventory_asset_assignments; v_status text;
begin perform public.inventory_require_access('assets',true); select * into v_assignment from public.inventory_asset_assignments where id=target_assignment_id and returned_at is null for update; if v_assignment.id is null then raise exception 'Current asset assignment not found'; end if; v_status:=case when coalesce(return_condition_value,'')='damaged' then 'maintenance' else 'available' end; update public.inventory_asset_assignments set returned_at=now(),returned_by=auth.uid(),return_condition=coalesce(nullif(return_condition_value,''),assignment_condition),return_notes=nullif(btrim(return_notes_text),'') where id=target_assignment_id returning * into v_assignment; update public.inventory_assets set asset_status=v_status,asset_condition=coalesce(nullif(return_condition_value,''),asset_condition),current_location_id=coalesce(target_location_id,current_location_id) where id=v_assignment.asset_id; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('asset_returned','asset',v_assignment.asset_id,jsonb_build_object('assignment_id',v_assignment.id,'condition',return_condition_value,'status',v_status),auth.uid()); return to_jsonb(v_assignment); end $function$

CREATE OR REPLACE FUNCTION public.inventory_return_stock(issue_movement_id uuid, quantity numeric, notes_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_issue public.inventory_stock_movements; v_returned numeric; v_id uuid;
begin perform public.inventory_require_access('stock',true); if quantity<=0 then raise exception 'Return quantity must be positive'; end if; select * into v_issue from public.inventory_stock_movements where id=issue_movement_id and movement_type='issue' and voided_at is null; if v_issue.id is null then raise exception 'Original issue movement not found'; end if; select coalesce(sum(quantity_delta),0) into v_returned from public.inventory_stock_movements where related_movement_id=v_issue.id and movement_type='return' and voided_at is null; if v_returned+quantity>abs(v_issue.quantity_delta) then raise exception 'Return quantity exceeds outstanding issued quantity'; end if; v_id:=public.inventory_record_stock_movement(v_issue.item_id,v_issue.location_id,'return',quantity,v_issue.unit_cost,'return',v_issue.reference_id,v_issue.reference_no,v_issue.id,v_issue.recipient_staff_id,v_issue.purpose,notes_text); return jsonb_build_object('movement_id',v_id,'balance',public.inventory_current_stock(v_issue.item_id,v_issue.location_id),'remaining_outstanding',abs(v_issue.quantity_delta)-v_returned-quantity); end $function$

CREATE OR REPLACE FUNCTION public.inventory_revoke_staff_access(target_access_id uuid, reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_staff_access;
begin perform public.inventory_require_access('staff_access',true); update public.inventory_staff_access set active=false,revoked_by=auth.uid(),revoked_at=now(),notes=case when coalesce(btrim(reason_text),'')<>'' then concat_ws(E'\n',notes,'Revoked: '||reason_text) else notes end where id=target_access_id and active and revoked_at is null returning * into v_row; if v_row.id is null then raise exception 'Active inventory staff appointment not found'; end if; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('inventory_staff_access_revoked','inventory_staff_access',v_row.id,jsonb_build_object('staff_id',v_row.staff_id,'access_role',v_row.access_role,'reason',reason_text),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_save_asset(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_row public.inventory_assets; v_item_type text;
begin perform public.inventory_require_access('assets',true); v_id:=nullif(payload->>'id','')::uuid; if nullif(payload->>'item_id','') is not null then select item_type into v_item_type from public.inventory_items where id=(payload->>'item_id')::uuid; if v_item_type<>'asset' then raise exception 'Asset register item must use an asset-type catalog item'; end if; end if;
  if v_id is null then insert into public.inventory_assets(asset_tag,item_id,asset_name,category,serial_number,model,manufacturer,supplier_id,purchase_date,purchase_cost,warranty_expires_on,current_location_id,asset_status,asset_condition,next_maintenance_on,notes,active,created_by) values(coalesce(nullif(btrim(payload->>'asset_tag'),''),public.inventory_generate_code('asset')),nullif(payload->>'item_id','')::uuid,coalesce(nullif(btrim(payload->>'asset_name'),''),'School asset'),nullif(btrim(payload->>'category'),''),nullif(btrim(payload->>'serial_number'),''),nullif(btrim(payload->>'model'),''),nullif(btrim(payload->>'manufacturer'),''),nullif(payload->>'supplier_id','')::uuid,nullif(payload->>'purchase_date','')::date,nullif(payload->>'purchase_cost','')::numeric,nullif(payload->>'warranty_expires_on','')::date,nullif(payload->>'current_location_id','')::uuid,'available',coalesce(nullif(payload->>'asset_condition',''),'good'),nullif(payload->>'next_maintenance_on','')::date,nullif(btrim(payload->>'notes'),''),true,auth.uid()) returning * into v_row;
  else update public.inventory_assets set asset_name=coalesce(nullif(btrim(payload->>'asset_name'),''),asset_name),category=case when payload?'category' then nullif(btrim(payload->>'category'),'') else category end,serial_number=case when payload?'serial_number' then nullif(btrim(payload->>'serial_number'),'') else serial_number end,model=case when payload?'model' then nullif(btrim(payload->>'model'),'') else model end,manufacturer=case when payload?'manufacturer' then nullif(btrim(payload->>'manufacturer'),'') else manufacturer end,supplier_id=case when payload?'supplier_id' then nullif(payload->>'supplier_id','')::uuid else supplier_id end,purchase_date=case when payload?'purchase_date' then nullif(payload->>'purchase_date','')::date else purchase_date end,purchase_cost=case when payload?'purchase_cost' then nullif(payload->>'purchase_cost','')::numeric else purchase_cost end,warranty_expires_on=case when payload?'warranty_expires_on' then nullif(payload->>'warranty_expires_on','')::date else warranty_expires_on end,current_location_id=case when payload?'current_location_id' then nullif(payload->>'current_location_id','')::uuid else current_location_id end,asset_condition=coalesce(nullif(payload->>'asset_condition',''),asset_condition),next_maintenance_on=case when payload?'next_maintenance_on' then nullif(payload->>'next_maintenance_on','')::date else next_maintenance_on end,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end where id=v_id and asset_status<>'disposed' returning * into v_row; end if;
  if v_row.id is null then raise exception 'Asset not found or cannot be edited'; end if; return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_save_item(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_row public.inventory_items; v_settings public.inventory_settings;
begin
  perform public.inventory_require_access('catalog',true); select * into v_settings from public.inventory_settings where singleton_key='default'; v_id:=nullif(payload->>'id','')::uuid;
  if v_id is null then
    insert into public.inventory_items(item_code,item_name,item_type,category,unit_of_measure,description,preferred_supplier_id,reorder_level,reorder_quantity,estimated_unit_cost,active,created_by)
    values(coalesce(nullif(btrim(payload->>'item_code'),''),public.inventory_generate_code('item')),coalesce(nullif(btrim(payload->>'item_name'),''),'Inventory item'),coalesce(nullif(payload->>'item_type',''),'consumable'),nullif(btrim(payload->>'category'),''),coalesce(nullif(btrim(payload->>'unit_of_measure'),''),'unit'),nullif(btrim(payload->>'description'),''),nullif(payload->>'preferred_supplier_id','')::uuid,coalesce(nullif(payload->>'reorder_level','')::numeric,v_settings.default_reorder_level),coalesce(nullif(payload->>'reorder_quantity','')::numeric,v_settings.default_reorder_quantity),nullif(payload->>'estimated_unit_cost','')::numeric,coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into v_row;
  else
    update public.inventory_items set item_name=coalesce(nullif(btrim(payload->>'item_name'),''),item_name),category=case when payload?'category' then nullif(btrim(payload->>'category'),'') else category end,unit_of_measure=coalesce(nullif(btrim(payload->>'unit_of_measure'),''),unit_of_measure),description=case when payload?'description' then nullif(btrim(payload->>'description'),'') else description end,preferred_supplier_id=case when payload?'preferred_supplier_id' then nullif(payload->>'preferred_supplier_id','')::uuid else preferred_supplier_id end,reorder_level=coalesce(nullif(payload->>'reorder_level','')::numeric,reorder_level),reorder_quantity=coalesce(nullif(payload->>'reorder_quantity','')::numeric,reorder_quantity),estimated_unit_cost=case when payload?'estimated_unit_cost' then nullif(payload->>'estimated_unit_cost','')::numeric else estimated_unit_cost end,active=coalesce((payload->>'active')::boolean,active) where id=v_id returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'Inventory item not found'; end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_save_location(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_row public.inventory_locations;
begin perform public.inventory_require_access('catalog',true); v_id:=nullif(payload->>'id','')::uuid;
  if v_id is null then insert into public.inventory_locations(code,name,location_type,description,active,created_by) values(upper(coalesce(nullif(btrim(payload->>'code'),''),'LOC-'||to_char(nextval('public.inventory_item_code_seq'),'FM000000'))),coalesce(nullif(btrim(payload->>'name'),''),'Inventory location'),coalesce(nullif(payload->>'location_type',''),'store'),nullif(btrim(payload->>'description'),''),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into v_row;
  else update public.inventory_locations set name=coalesce(nullif(btrim(payload->>'name'),''),name),location_type=coalesce(nullif(payload->>'location_type',''),location_type),description=case when payload?'description' then nullif(btrim(payload->>'description'),'') else description end,active=coalesce((payload->>'active')::boolean,active) where id=v_id returning * into v_row; end if;
  if v_row.id is null then raise exception 'Inventory location not found'; end if; return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_save_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.inventory_settings;
begin perform public.inventory_require_access('settings',true); update public.inventory_settings set currency=coalesce(nullif(upper(btrim(payload->>'currency')),''),currency),default_reorder_level=coalesce(nullif(payload->>'default_reorder_level','')::numeric,default_reorder_level),default_reorder_quantity=coalesce(nullif(payload->>'default_reorder_quantity','')::numeric,default_reorder_quantity),low_stock_alerts=coalesce((payload->>'low_stock_alerts')::boolean,low_stock_alerts),asset_maintenance_alert_days=coalesce(nullif(payload->>'asset_maintenance_alert_days','')::integer,asset_maintenance_alert_days) where singleton_key='default' returning * into v_row; return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_save_staff_access(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_staff uuid; v_profile uuid; v_role text; v_existing uuid; v_row public.inventory_staff_access;
begin
  perform public.inventory_require_access('staff_access',true);
  v_staff:=nullif(payload->>'staff_id','')::uuid;
  v_role:=nullif(payload->>'access_role','');
  if v_role not in ('inventory_manager','procurement_officer','storekeeper','asset_officer','inventory_auditor') then raise exception 'Invalid inventory staff role'; end if;
  select profile_id into v_profile from public.hr_staff_members where id=v_staff and active and deleted_at is null and profile_id is not null;
  if v_profile is null then raise exception 'Active HR staff profile is required'; end if;
  select id into v_existing from public.inventory_staff_access where staff_id=v_staff and active and revoked_at is null;
  if v_existing is not null then
    update public.inventory_staff_access set access_role=v_role,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end,updated_at=now() where id=v_existing returning * into v_row;
  else
    insert into public.inventory_staff_access(staff_id,profile_id,access_role,appointed_by,notes) values(v_staff,v_profile,v_role,auth.uid(),nullif(btrim(payload->>'notes'),'')) returning * into v_row;
  end if;
  update public.profiles set mfa_required=true where id=v_profile and coalesce(mfa_required,false)=false;
  insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('inventory_staff_access_saved','inventory_staff_access',v_row.id,jsonb_build_object('staff_id',v_staff,'access_role',v_role,'mfa_required',true),auth.uid());
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_save_supplier(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_row public.inventory_suppliers;
begin perform public.inventory_require_access('procurement',true); v_id:=nullif(payload->>'id','')::uuid;
  if v_id is null then insert into public.inventory_suppliers(supplier_code,supplier_name,contact_name,phone,email,address,tax_id,payment_terms,notes,active,created_by) values(coalesce(nullif(btrim(payload->>'supplier_code'),''),public.inventory_generate_code('supplier')),coalesce(nullif(btrim(payload->>'supplier_name'),''),'Supplier'),nullif(btrim(payload->>'contact_name'),''),nullif(btrim(payload->>'phone'),''),nullif(btrim(payload->>'email'),''),nullif(btrim(payload->>'address'),''),nullif(btrim(payload->>'tax_id'),''),nullif(btrim(payload->>'payment_terms'),''),nullif(btrim(payload->>'notes'),''),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into v_row;
  else update public.inventory_suppliers set supplier_name=coalesce(nullif(btrim(payload->>'supplier_name'),''),supplier_name),contact_name=case when payload?'contact_name' then nullif(btrim(payload->>'contact_name'),'') else contact_name end,phone=case when payload?'phone' then nullif(btrim(payload->>'phone'),'') else phone end,email=case when payload?'email' then nullif(btrim(payload->>'email'),'') else email end,address=case when payload?'address' then nullif(btrim(payload->>'address'),'') else address end,tax_id=case when payload?'tax_id' then nullif(btrim(payload->>'tax_id'),'') else tax_id end,payment_terms=case when payload?'payment_terms' then nullif(btrim(payload->>'payment_terms'),'') else payment_terms end,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end,active=coalesce((payload->>'active')::boolean,active) where id=v_id returning * into v_row; end if;
  if v_row.id is null then raise exception 'Supplier not found'; end if; return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_license jsonb; v_staff uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_access:=public.inventory_access_snapshot();
  v_license:=public.license_access_for_actor(auth.uid());
  select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and active and deleted_at is null limit 1;
  return v_access || jsonb_build_object('read_allowed',coalesce((v_license->>'read_allowed')::boolean,false),'write_allowed',coalesce((v_license->>'write_allowed')::boolean,false),'self_service',v_staff is not null);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_settings_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ begin perform public.inventory_require_access('view',false); return (select to_jsonb(s) from public.inventory_settings s where singleton_key='default'); end $function$

CREATE OR REPLACE FUNCTION public.inventory_staff_access_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('staff_access',false); return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'staff_id',a.staff_id,'profile_id',a.profile_id,'access_role',a.access_role,'active',a.active,'appointed_at',a.appointed_at,'revoked_at',a.revoked_at,'notes',a.notes,'staff_no',h.staff_no,'full_name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),'department',h.department,'job_title',h.job_title) order by a.active desc,a.appointed_at desc) from public.inventory_staff_access a join public.hr_staff_members h on h.id=a.staff_id),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_staff_candidates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.inventory_require_access('staff_access',false); return coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'profile_id',h.profile_id,'staff_no',h.staff_no,'full_name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),'department',h.department,'job_title',h.job_title,'email',h.email,'phone',h.phone,'current_inventory_role',a.access_role) order by h.last_name,h.first_name) from public.hr_staff_members h left join public.inventory_staff_access a on a.staff_id=h.id and a.active and a.revoked_at is null where h.active and h.deleted_at is null and h.profile_id is not null),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_staff_directory(search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb;
begin
  v_access:=public.inventory_require_access('view',false);
  if not (coalesce((v_access->>'stock')::boolean,false) or coalesce((v_access->>'assets')::boolean,false)) then
    raise exception 'Inventory staff directory is not available for this role' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'staff_no',h.staff_no,'full_name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),'department',h.department,'job_title',h.job_title) order by h.last_name,h.first_name)
    from public.hr_staff_members h
    where h.active and h.deleted_at is null and h.profile_id is not null
      and (coalesce(nullif(search_text,''),'')='' or h.staff_no ilike '%'||search_text||'%' or btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))) ilike '%'||search_text||'%' or coalesce(h.department,'') ilike '%'||search_text||'%')),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_stock_movement_register(search_text text DEFAULT NULL::text, location_filter uuid DEFAULT NULL::uuid, movement_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.inventory_require_access('view',false);
  return coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'item_id',m.item_id,'item_code',i.item_code,'item_name',i.item_name,'unit_of_measure',i.unit_of_measure,'location_id',m.location_id,'location_name',l.name,'movement_type',m.movement_type,'quantity_delta',m.quantity_delta,'unit_cost',m.unit_cost,'reference_type',m.reference_type,'reference_no',m.reference_no,'related_movement_id',m.related_movement_id,'recipient_staff_id',m.recipient_staff_id,'recipient_name',case when h.id is null then null else btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))) end,'purpose',m.purpose,'notes',m.notes,'posted_at',m.posted_at) order by m.posted_at desc)
    from (select * from public.inventory_stock_movements where voided_at is null order by posted_at desc limit 300) m
    join public.inventory_items i on i.id=m.item_id
    join public.inventory_locations l on l.id=m.location_id
    left join public.hr_staff_members h on h.id=m.recipient_staff_id
    where (location_filter is null or m.location_id=location_filter)
      and (coalesce(nullif(movement_filter,''),'')='' or m.movement_type=movement_filter)
      and (coalesce(nullif(search_text,''),'')='' or i.item_code ilike '%'||search_text||'%' or i.item_name ilike '%'||search_text||'%' or coalesce(m.reference_no,'') ilike '%'||search_text||'%')),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.inventory_stock_register(search_text text DEFAULT NULL::text, location_filter uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.inventory_require_access('view',false);
  return jsonb_build_object(
    'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'code',l.code,'name',l.name,'location_type',l.location_type) order by l.name) from public.inventory_locations l where l.active),'[]'::jsonb),
    'rows',coalesce((select jsonb_agg(jsonb_build_object('item_id',i.id,'item_code',i.item_code,'item_name',i.item_name,'category',i.category,'unit_of_measure',i.unit_of_measure,'location_id',l.id,'location_name',l.name,'quantity',coalesce((select sum(m.quantity_delta) from public.inventory_stock_movements m where m.item_id=i.id and m.location_id=l.id and m.voided_at is null),0),'reorder_level',i.reorder_level,'low_stock',coalesce((select sum(m.quantity_delta) from public.inventory_stock_movements m where m.item_id=i.id and m.location_id=l.id and m.voided_at is null),0)<=i.reorder_level) order by i.item_name,l.name) from public.inventory_items i cross join public.inventory_locations l where i.active and i.item_type='consumable' and l.active and (location_filter is null or l.id=location_filter) and (coalesce(nullif(search_text,''),'')='' or i.item_code ilike '%'||search_text||'%' or i.item_name ilike '%'||search_text||'%')),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.inventory_submit_my_item_request(target_item_id uuid, quantity numeric, purpose_text text, preferred_location_uuid uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_staff uuid; v_license jsonb; v_row public.inventory_item_requests;
begin if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if; v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Inventory requests are unavailable while the school licence is read-only' using errcode='42501'; end if; select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and active and deleted_at is null; if v_staff is null then raise exception 'Active staff record not found' using errcode='42501'; end if; if quantity<=0 then raise exception 'Requested quantity must be positive'; end if; if not exists(select 1 from public.inventory_items where id=target_item_id and active and item_type='consumable') then raise exception 'Active consumable item not found'; end if; insert into public.inventory_item_requests(request_no,staff_id,item_id,quantity,purpose,preferred_location_id) values(public.inventory_generate_code('request'),v_staff,target_item_id,quantity,coalesce(nullif(btrim(purpose_text),''),'Staff request'),preferred_location_uuid) returning * into v_row; insert into public.inventory_events(event_type,entity_type,entity_id,details,actor_id) values('item_request_submitted','item_request',v_row.id,jsonb_build_object('request_no',v_row.request_no,'staff_id',v_staff,'item_id',target_item_id,'quantity',quantity),auth.uid()); return to_jsonb(v_row); end $function$

CREATE OR REPLACE FUNCTION public.inventory_suppliers_register(search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ begin perform public.inventory_require_access('view',false); return coalesce((select jsonb_agg(to_jsonb(s) order by s.active desc,s.supplier_name) from public.inventory_suppliers s where coalesce(nullif(search_text,''),'')='' or s.supplier_code ilike '%'||search_text||'%' or s.supplier_name ilike '%'||search_text||'%' or coalesce(s.contact_name,'') ilike '%'||search_text||'%'),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.inventory_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$ begin new.updated_at:=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.inventory_transfer_stock(target_item_id uuid, from_location_id uuid, to_location_id uuid, quantity numeric, reason_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_ref text; v_out uuid; v_in uuid;
begin perform public.inventory_require_access('stock',true); if quantity<=0 then raise exception 'Transfer quantity must be positive'; end if; if from_location_id=to_location_id then raise exception 'Transfer locations must be different'; end if; v_ref:='TRF-'||replace(gen_random_uuid()::text,'-',''); v_out:=public.inventory_record_stock_movement(target_item_id,from_location_id,'transfer_out',-quantity,null,'transfer',null,v_ref,null,null,reason_text,reason_text); v_in:=public.inventory_record_stock_movement(target_item_id,to_location_id,'transfer_in',quantity,null,'transfer',null,v_ref,v_out,null,reason_text,reason_text); return jsonb_build_object('reference_no',v_ref,'out_movement_id',v_out,'in_movement_id',v_in,'from_balance',public.inventory_current_stock(target_item_id,from_location_id),'to_balance',public.inventory_current_stock(target_item_id,to_location_id)); end $function$

CREATE OR REPLACE FUNCTION public.is_academic_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(
    public.has_role(array['system_admin'])
    and public.current_aal()='aal2',
    false
  )
$function$

CREATE OR REPLACE FUNCTION public.is_assigned_class_teacher(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role()='class_teacher'
    and exists(
      select 1 from public.classes c
      where c.id=target_class_id
        and c.class_teacher_id=auth.uid()
        and c.active
        and c.deleted_at is null
    )
$function$

CREATE OR REPLACE FUNCTION public.is_official_class_teacher_for_class(target_class_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.classes c
    where c.id=target_class_id and c.class_teacher_id=target_user_id
      and c.active and c.deleted_at is null
  )
$function$

CREATE OR REPLACE FUNCTION public.is_official_subject_teacher_for_class(target_class_id uuid, target_subject_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.class_subjects cs
    join public.classes c on c.id=cs.class_id
    join public.subjects s on s.id=cs.subject_id
    where cs.class_id=target_class_id and cs.subject_id=target_subject_id
      and cs.teacher_id=target_user_id and cs.active
      and c.active and c.deleted_at is null
      and s.active and s.deleted_at is null
  )
$function$

CREATE OR REPLACE FUNCTION public.is_platform_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(public.current_app_role()::text='platform_super_admin',false)
$function$

CREATE OR REPLACE FUNCTION public.is_records_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.has_role(array['system_admin']) and public.current_aal()='aal2'
$function$

CREATE OR REPLACE FUNCTION public.is_system_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.has_role(array['system_admin']) $function$

CREATE OR REPLACE FUNCTION public.is_term_three(term_sequence integer, term_name text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select coalesce(term_sequence=3,false)
    or lower(regexp_replace(coalesce(term_name,''),'[^a-zA-Z0-9]+','','g'))
       in ('term3','termthree','thirdterm','3rdterm')
$function$

CREATE OR REPLACE FUNCTION public.issue_certificate_batch(target_batch_id uuid, target_issue_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare batch_row public.certificate_batches; item record; school public.school_settings; principal record; year_code text; cert_number text; issued_count integer:=0;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can issue approved certificates' using errcode='42501'; end if;
  select * into batch_row from public.certificate_batches where id=target_batch_id for update;
  if batch_row.id is null or batch_row.status<>'approved' then raise exception 'Only an approved certificate batch can be issued'; end if;
  if target_issue_date is null or target_issue_date>current_date then raise exception 'Certificate issue date cannot be in the future'; end if;
  if not exists(select 1 from public.certificates where batch_id=target_batch_id and status='approved') then raise exception 'The approved batch contains no issuable certificates'; end if;
  select * into school from public.school_settings limit 1;
  select h.id,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,h.signature_path into principal from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active' and btrim(coalesce(h.signature_path,''))<>'' order by case when h.profile_id=batch_row.approved_by then 0 else 1 end,h.created_at limit 1;
  if principal.id is null then raise exception 'An active Principal signature is required before certificates can be issued'; end if;
  select regexp_replace(name::text,'[^0-9]+','','g') into year_code from public.academic_years where id=batch_row.academic_year_id;
  if year_code='' then year_code:=extract(year from target_issue_date)::text; end if;
  for item in select * from public.certificates where batch_id=target_batch_id and status='approved' order by recipient_name for update loop
    cert_number:=upper(coalesce(nullif(school.report_number_prefix,''),'RCE'))||'/'||left(year_code,9)||'/'||public.certificate_type_code(batch_row.certificate_type)||'/'||lpad(nextval('public.certificate_number_seq')::text,6,'0');
    update public.certificates set certificate_number=cert_number,issue_date=coalesce(target_issue_date,current_date),status='issued',issued_by=auth.uid(),issued_at=now(),snapshot=snapshot||jsonb_build_object('school',to_jsonb(school),'principal',jsonb_build_object('full_name',principal.full_name,'signature_path',principal.signature_path),'certificate_number',cert_number,'issue_date',coalesce(target_issue_date,current_date),'verification_token',verification_token),updated_at=now() where id=item.id;
    if item.supersedes_certificate_id is not null then
      update public.certificates set status='superseded',updated_at=now() where id=item.supersedes_certificate_id and status='issued';
      perform public.record_certificate_event(target_batch_id,item.supersedes_certificate_id,'superseded','Replaced by '||cert_number,jsonb_build_object('replacement_certificate_id',item.id));
    end if;
    perform public.record_certificate_event(target_batch_id,item.id,'issued','',jsonb_build_object('certificate_number',cert_number));
    issued_count:=issued_count+1;
  end loop;
  update public.certificate_batches set status='issued',issued_by=auth.uid(),issued_at=now(),updated_at=now() where id=target_batch_id;
  return jsonb_build_object('batch_id',target_batch_id,'status','issued','issued_count',issued_count,'certificates',(select jsonb_agg(jsonb_build_object('id',id,'certificate_number',certificate_number,'recipient_name',recipient_name,'verification_token',verification_token) order by recipient_name) from public.certificates where batch_id=target_batch_id and status='issued'));
end $function$

CREATE OR REPLACE FUNCTION public.issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare key text;parts text[];kind text;sid uuid;cfg public.id_card_settings%rowtype;card_id uuid;card_number text;token uuid;expires date:=target_expires_on;created jsonb:='[]'::jsonb;skipped jsonb:='[]'::jsonb;snap jsonb;existing uuid;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can issue staff ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card issuance' using errcode='42501';end if;if target_academic_year_id is null then raise exception 'Academic year is required';end if;if target_issue_date is null then raise exception 'Issue date is required';end if;if coalesce(array_length(target_staff_keys,1),0)=0 then raise exception 'Select at least one staff member';end if;insert into public.id_card_settings default values on conflict do nothing;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.staff_validity_months,24)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'Staff ID card expiry date cannot be before issue date';end if;
  foreach key in array target_staff_keys loop parts:=string_to_array(key,':');kind:=coalesce(parts[1],'');sid:=public.safe_uuid(coalesce(parts[2],''));if kind not in ('teacher','principal') or sid is null then raise exception 'Invalid staff selection';end if;perform pg_advisory_xact_lock(hashtext('rce-staff-id-'||kind||'-'||sid::text));existing:=null;if kind='teacher' then select id into existing from public.staff_id_cards where teacher_id=sid and status='active' order by issued_at desc limit 1 for update;else select id into existing from public.staff_id_cards where headteacher_id=sid and status='active' order by issued_at desc limit 1 for update;end if;if existing is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('staff_key',key,'reason','active_card_exists'));continue;end if;card_number:=public.generate_staff_id_card_number(target_academic_year_id);token:=gen_random_uuid();snap:=public.build_staff_id_card_snapshot(kind,sid,target_academic_year_id,card_number,token,target_issue_date,expires);insert into public.staff_id_cards(staff_type,teacher_id,headteacher_id,academic_year_id,card_number,verification_token,issue_date,expires_on,snapshot,issued_by) values(kind,case when kind='teacher' then sid else null end,case when kind='principal' then sid else null end,target_academic_year_id,card_number,token,target_issue_date,expires,snap,auth.uid()) returning id into card_id;perform public.record_staff_id_card_event(card_id,kind,sid,'issued',jsonb_build_object('card_number',card_number,'academic_year_id',target_academic_year_id,'expires_on',expires));created:=created||jsonb_build_array(jsonb_build_object('card_id',card_id,'staff_key',key,'card_number',card_number,'verification_token',token));end loop;
  return jsonb_build_object('created',created,'created_count',jsonb_array_length(created),'skipped',skipped,'skipped_count',jsonb_array_length(skipped),'issue_date',target_issue_date,'expires_on',expires);
end$function$

CREATE OR REPLACE FUNCTION public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare sid uuid;e public.enrollments%rowtype;cfg public.id_card_settings%rowtype;card_id uuid;card_number text;token uuid;expires date:=target_expires_on;created jsonb:='[]'::jsonb;skipped jsonb:='[]'::jsonb;snap jsonb;existing public.student_id_cards%rowtype; begin if not public.is_system_admin() then raise exception 'Only the System Administrator can issue student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card issuance' using errcode='42501';end if;if target_academic_year_id is null or target_class_id is null then raise exception 'Academic year and class are required';end if;if target_issue_date is null then raise exception 'ID card issue date is required';end if;if coalesce(array_length(target_student_ids,1),0)=0 then raise exception 'Select at least one student';end if; perform pg_advisory_xact_lock(hashtext('rce-id-card-issue-'||target_academic_year_id::text||'-'||target_class_id::text));insert into public.id_card_settings default values on conflict do nothing;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.validity_months,12)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'ID card expiry date cannot be before the issue date';end if; foreach sid in array target_student_ids loop select * into e from public.enrollments where student_id=sid and academic_year_id=target_academic_year_id and class_id=target_class_id and active and deleted_at is null limit 1;if e.id is null then raise exception 'Selected student % is not actively enrolled in the selected class and academic year',sid;end if; select * into existing from public.student_id_cards where student_id=sid and academic_year_id=target_academic_year_id and status='active' order by issued_at desc limit 1 for update; if existing.id is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',sid,'card_id',existing.id,'card_number',existing.card_number,'reason','active_card_exists'));continue;end if; card_number:=public.generate_student_id_card_number(target_academic_year_id);token:=gen_random_uuid();snap:=public.build_student_id_card_snapshot(sid,e.id,card_number,token,target_issue_date,expires); insert into public.student_id_cards(student_id,enrollment_id,academic_year_id,class_id,card_number,verification_token,issue_date,expires_on,snapshot,issued_by) values(sid,e.id,target_academic_year_id,target_class_id,card_number,token,target_issue_date,expires,snap,auth.uid()) returning id into card_id;perform public.record_id_card_event(card_id,sid,'issued',jsonb_build_object('card_number',card_number,'academic_year_id',target_academic_year_id,'class_id',target_class_id,'expires_on',expires));created:=created||jsonb_build_array(jsonb_build_object('card_id',card_id,'student_id',sid,'card_number',card_number,'verification_token',token));existing:=null; end loop; return jsonb_build_object('created',created,'created_count',jsonb_array_length(created),'skipped',skipped,'skipped_count',jsonb_array_length(skipped),'issue_date',target_issue_date,'expires_on',expires); end$function$

CREATE OR REPLACE FUNCTION public.issue_student_transcript(target_student_id uuid, purpose_text text DEFAULT 'Academic transcript'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  issued public.transcript_issuances;
  transcript_snapshot jsonb;
  transcript_no text;
  checksum_text text;
  periods integer;
  latest_year text;
  latest_term_text text;
  latest_class_text text;
  school_prefix text;
begin
  if public.current_app_role() not in ('system_admin','principal') then
    raise exception 'Only the System Administrator or Principal can issue a transcript' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'The current licence does not permit transcript issuance' using errcode='42501';
  end if;

  transcript_snapshot:=public.build_student_transcript_snapshot(target_student_id);
  periods:=coalesce((transcript_snapshot->'summary'->>'academic_period_count')::integer,0);
  if periods<1 then
    raise exception 'No published academic results are available for official transcript issuance' using errcode='22023';
  end if;

  select upper(coalesce(nullif(split_part(ss.tenant_code,'-',1),''),'SCH'))
    into school_prefix
  from public.school_settings ss
  order by ss.created_at,ss.id
  limit 1;
  school_prefix:=coalesce(nullif(regexp_replace(school_prefix,'[^A-Z0-9]','','g'),''),'SCH');
  transcript_no:=school_prefix||'-TR-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.transcript_number_seq')::text,6,'0');
  checksum_text:=encode(extensions.digest(convert_to(transcript_snapshot::text,'UTF8'),'sha256'),'hex');
  latest_year:=coalesce(transcript_snapshot->'summary'->>'latest_academic_year','');
  latest_term_text:=coalesce(transcript_snapshot->'summary'->>'latest_term','');
  latest_class_text:=coalesce(transcript_snapshot->'summary'->>'latest_class','');

  update public.transcript_issuances
    set status='superseded'
  where student_id=target_student_id and status='valid';

  insert into public.transcript_issuances(
    student_id,transcript_number,purpose,snapshot,snapshot_checksum,academic_period_count,
    latest_academic_year,latest_term,latest_class,template_version
  ) values(
    target_student_id,transcript_no,left(coalesce(nullif(btrim(purpose_text),''),'Academic transcript'),250),
    transcript_snapshot,checksum_text,periods,latest_year,latest_term_text,latest_class_text,'professional-transcript-v1'
  ) returning * into issued;

  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason)
  values(
    auth.uid(),'transcript_issuances',issued.id,'ISSUE',
    jsonb_build_object(
      'transcript_number',issued.transcript_number,
      'student_id',issued.student_id,
      'purpose',issued.purpose,
      'academic_period_count',issued.academic_period_count,
      'latest_academic_year',issued.latest_academic_year,
      'latest_term',issued.latest_term,
      'template_version',issued.template_version,
      'snapshot_checksum',issued.snapshot_checksum
    ),issued.purpose
  );

  return jsonb_build_object(
    'id',issued.id,'transcript_number',issued.transcript_number,'verification_token',issued.verification_token,
    'purpose',issued.purpose,'status',issued.status,'issued_at',issued.issued_at,
    'snapshot_checksum',issued.snapshot_checksum,'academic_period_count',issued.academic_period_count,
    'latest_academic_year',issued.latest_academic_year,'latest_term',issued.latest_term,
    'latest_class',issued.latest_class,'template_version',issued.template_version,'snapshot',issued.snapshot
  );
end
$function$

CREATE OR REPLACE FUNCTION public.library_actor_access()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r text; a public.library_staff_access;
begin
  if auth.uid() is null then return jsonb_build_object('authorized',false,'role',null,'capabilities','[]'::jsonb); end if;
  r:=public.current_app_role()::text;
  if r='system_admin' then
    return jsonb_build_object('authorized',true,'role','system_admin','capabilities',jsonb_build_array('view','catalog_write','circulate','manage_access','manage_settings'));
  elsif r='principal' then
    return jsonb_build_object('authorized',true,'role','principal','capabilities',jsonb_build_array('view'));
  end if;
  select * into a from public.library_staff_access where profile_id=auth.uid() and active;
  if a.id is null then return jsonb_build_object('authorized',false,'role',null,'capabilities','[]'::jsonb); end if;
  if a.library_role='librarian' then
    return jsonb_build_object('authorized',true,'role','librarian','capabilities',jsonb_build_array('view','catalog_write','circulate','manage_settings'));
  end if;
  return jsonb_build_object('authorized',true,'role','assistant','capabilities',jsonb_build_array('view','circulate'));
end $function$

CREATE OR REPLACE FUNCTION public.library_block_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if current_setting('app.library_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'Library history cannot be hard deleted; use status, withdrawal or cancellation instead' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.library_book_detail(target_book_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_book jsonb;
begin
  perform public.library_require_access(false,'view');
  select to_jsonb(b) into v_book from public.library_books b where b.id=target_book_id and b.deleted_at is null;
  if v_book is null then raise exception 'Library title not found'; end if;
  return jsonb_build_object('book',v_book,'copies',coalesce((select jsonb_agg(to_jsonb(c) order by c.accession_no) from public.library_copies c where c.book_id=target_book_id and c.deleted_at is null),'[]'::jsonb),'reservations',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'borrower_type',r.borrower_type,'borrower',case when r.borrower_type='student' then concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) else concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) end,'status',r.status,'reserved_at',r.reserved_at,'ready_at',r.ready_at,'expires_at',r.expires_at) order by r.reserved_at) from public.library_reservations r left join public.students s on s.id=r.borrower_student_id left join public.hr_staff_members h on h.id=r.borrower_hr_staff_id where r.book_id=target_book_id and r.status in ('waiting','ready')),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.library_cancel_my_reservation(target_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r text; v_license jsonb; v_row public.library_reservations;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Library reservations are unavailable while the school licence is read-only' using errcode='42501'; end if;
  r:=public.current_app_role()::text;
  update public.library_reservations rv set status='cancelled' where rv.id=target_reservation_id and rv.status in ('waiting','ready') and ((r='student' and exists(select 1 from public.students s where s.id=rv.borrower_student_id and s.profile_id=auth.uid())) or (r not in ('student','parent_guardian','platform_super_admin') and exists(select 1 from public.hr_staff_members h where h.id=rv.borrower_hr_staff_id and h.profile_id=auth.uid()))) returning * into v_row;
  if v_row.id is null then raise exception 'Active reservation not found or not owned by this user'; end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.library_catalog_register(search_text text DEFAULT NULL::text, category_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.library_require_access(false,'view');
  return jsonb_build_object(
    'rows',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'isbn',b.isbn,'title',b.title,'subtitle',b.subtitle,'author',b.author,'publisher',b.publisher,'publication_year',b.publication_year,'edition',b.edition,'category',b.category,'subject',b.subject,'language',b.language,'active',b.active,
      'copies_total',(select count(*) from public.library_copies c where c.book_id=b.id and c.deleted_at is null and c.active),
      'copies_available',(select count(*) from public.library_copies c where c.book_id=b.id and c.deleted_at is null and c.active and c.circulation_status='available'),
      'copies_on_loan',(select count(*) from public.library_copies c where c.book_id=b.id and c.deleted_at is null and c.active and c.circulation_status='on_loan'),
      'reservations',(select count(*) from public.library_reservations r where r.book_id=b.id and r.status in ('waiting','ready'))
    ) order by b.title,b.author) from public.library_books b where b.deleted_at is null and (coalesce(nullif(search_text,''),'')='' or b.title ilike '%'||search_text||'%' or b.author ilike '%'||search_text||'%' or coalesce(b.isbn,'') ilike '%'||search_text||'%') and (coalesce(nullif(category_filter,''),'')='' or coalesce(b.category,'')=category_filter)),'[]'::jsonb),
    'categories',coalesce((select jsonb_agg(x.category order by x.category) from (select distinct category from public.library_books where deleted_at is null and coalesce(category,'')<>'') x),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.library_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.library_require_access(false,'view');
  return jsonb_build_object(
    'metrics',jsonb_build_object(
      'titles',(select count(*) from public.library_books where deleted_at is null and active),
      'copies',(select count(*) from public.library_copies where deleted_at is null and active),
      'available',(select count(*) from public.library_copies where deleted_at is null and active and circulation_status='available'),
      'on_loan',(select count(*) from public.library_loans where status='issued' and returned_at is null),
      'overdue',(select count(*) from public.library_loans where status='issued' and returned_at is null and due_date<current_date),
      'reservations',(select count(*) from public.library_reservations where status in ('waiting','ready'))
    ),
    'recent_loans',coalesce((select jsonb_agg(x order by x->>'issued_at' desc) from (
      select jsonb_build_object('loan_id',l.id,'title',b.title,'accession_no',c.accession_no,'borrower',case when l.borrower_type='student' then concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) else concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) end,'borrower_type',l.borrower_type,'issued_at',l.issued_at,'due_date',l.due_date,'status',case when l.status='issued' and l.due_date<current_date then 'overdue' else l.status end) x
      from public.library_loans l join public.library_copies c on c.id=l.copy_id join public.library_books b on b.id=c.book_id
      left join public.students s on s.id=l.borrower_student_id left join public.hr_staff_members h on h.id=l.borrower_hr_staff_id
      order by l.issued_at desc limit 10
    ) q),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.library_generate_accession_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint; candidate text;
begin
  select coalesce(nullif(regexp_replace(upper(identifier_root),'[^A-Z0-9]','','g'),''),nullif(regexp_replace(upper(school_name),'[^A-Z]','','g'),''),'SCH') into root from public.school_settings limit 1;
  root:=left(root,8);
  loop
    n:=nextval('public.library_accession_seq');
    candidate:=root||'-LIB-'||lpad(n::text,6,'0');
    exit when not exists(select 1 from public.library_copies where accession_no=candidate);
  end loop;
  return candidate;
end $function$

CREATE OR REPLACE FUNCTION public.library_issue_copy(target_copy_id uuid, borrower_kind text, borrower_id uuid, due_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_copy public.library_copies; v_settings public.library_settings; v_count integer; v_due date; v_loan public.library_loans; v_res uuid;
begin
  perform public.library_require_access(true,'circulate');
  select * into v_copy from public.library_copies where id=target_copy_id and deleted_at is null and active for update;
  if v_copy.id is null then raise exception 'Library copy not found'; end if;
  if v_copy.circulation_status<>'available' then raise exception 'Library copy is not available'; end if;
  select * into v_settings from public.library_settings limit 1;
  if borrower_kind='student' then
    if not exists(select 1 from public.students where id=borrower_id and deleted_at is null) then raise exception 'Active student borrower not found'; end if;
    select count(*) into v_count from public.library_loans where borrower_student_id=borrower_id and status='issued' and returned_at is null;
    if v_count>=v_settings.student_max_loans then raise exception 'Student has reached the maximum active loan limit'; end if;
    v_due:=coalesce(due_on,current_date+v_settings.student_loan_days);
    insert into public.library_loans(copy_id,borrower_type,borrower_student_id,due_date,issued_by) values(v_copy.id,'student',borrower_id,v_due,auth.uid()) returning * into v_loan;
    select id into v_res from public.library_reservations where book_id=v_copy.book_id and borrower_student_id=borrower_id and status in ('waiting','ready') order by reserved_at limit 1 for update;
  elsif borrower_kind='staff' then
    if not exists(select 1 from public.hr_staff_members where id=borrower_id and deleted_at is null and active) then raise exception 'Active staff borrower not found'; end if;
    select count(*) into v_count from public.library_loans where borrower_hr_staff_id=borrower_id and status='issued' and returned_at is null;
    if v_count>=v_settings.staff_max_loans then raise exception 'Staff member has reached the maximum active loan limit'; end if;
    v_due:=coalesce(due_on,current_date+v_settings.staff_loan_days);
    insert into public.library_loans(copy_id,borrower_type,borrower_hr_staff_id,due_date,issued_by) values(v_copy.id,'staff',borrower_id,v_due,auth.uid()) returning * into v_loan;
    select id into v_res from public.library_reservations where book_id=v_copy.book_id and borrower_hr_staff_id=borrower_id and status in ('waiting','ready') order by reserved_at limit 1 for update;
  else raise exception 'Borrower type must be student or staff'; end if;
  update public.library_copies set circulation_status='on_loan' where id=v_copy.id;
  if v_res is not null then update public.library_reservations set status='fulfilled',fulfilled_loan_id=v_loan.id where id=v_res; end if;
  insert into public.library_inventory_events(copy_id,event_type,details,actor_id) values(v_copy.id,'loan_issued',jsonb_build_object('loan_id',v_loan.id,'borrower_type',borrower_kind,'borrower_id',borrower_id,'due_date',v_due),auth.uid());
  return to_jsonb(v_loan);
end $function$

CREATE OR REPLACE FUNCTION public.library_loan_register(status_filter text DEFAULT NULL::text, search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.library_require_access(false,'view');
  return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'copy_id',c.id,'book_id',b.id,'title',b.title,'author',b.author,'accession_no',c.accession_no,'borrower_type',l.borrower_type,'borrower_id',case when l.borrower_type='student' then l.borrower_student_id else l.borrower_hr_staff_id end,'borrower',case when l.borrower_type='student' then concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) else btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))) end,'reference_no',case when l.borrower_type='student' then s.admission_no::text else h.staff_no end,'issued_at',l.issued_at,'due_date',l.due_date,'returned_at',l.returned_at,'renew_count',l.renew_count,'status',case when l.status='issued' and l.returned_at is null and l.due_date<current_date then 'overdue' else l.status end) order by case when l.status='issued' and l.due_date<current_date then 0 when l.status='issued' then 1 else 2 end,l.due_date,l.issued_at desc) from public.library_loans l join public.library_copies c on c.id=l.copy_id join public.library_books b on b.id=c.book_id left join public.students s on s.id=l.borrower_student_id left join public.hr_staff_members h on h.id=l.borrower_hr_staff_id where (coalesce(nullif(status_filter,''),'')='' or status_filter=case when l.status='issued' and l.returned_at is null and l.due_date<current_date then 'overdue' else l.status end) and (coalesce(nullif(search_text,''),'')='' or b.title ilike '%'||search_text||'%' or c.accession_no ilike '%'||search_text||'%' or coalesce(s.admission_no::text,'') ilike '%'||search_text||'%' or coalesce(h.staff_no,'') ilike '%'||search_text||'%' or coalesce(s.first_name,'') ilike '%'||search_text||'%' or coalesce(s.last_name,'') ilike '%'||search_text||'%' or coalesce(h.first_name,'') ilike '%'||search_text||'%' or coalesce(h.last_name,'') ilike '%'||search_text||'%')),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.library_member_search(search_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.library_require_access(false,'circulate');
  if length(coalesce(btrim(search_text),''))<2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'name') from (
      select jsonb_build_object(
        'borrower_type','student',
        'borrower_id',s.id,
        'reference_no',s.admission_no::text,
        'name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'detail','Student'
      ) x
      from public.students s
      where s.deleted_at is null
        and (s.admission_no::text ilike '%'||search_text||'%' or s.first_name ilike '%'||search_text||'%' or s.last_name ilike '%'||search_text||'%')
      union all
      select jsonb_build_object(
        'borrower_type','staff',
        'borrower_id',h.id,
        'reference_no',h.staff_no,
        'name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),
        'detail',coalesce(h.department,'Staff')
      )
      from public.hr_staff_members h
      where h.deleted_at is null
        and h.active
        and (h.staff_no ilike '%'||search_text||'%' or h.first_name ilike '%'||search_text||'%' or h.last_name ilike '%'||search_text||'%')
      limit 30
    ) q
  ),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.library_my_account()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r text; v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  r:=public.current_app_role()::text; v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Library account unavailable while school licence is locked' using errcode='42501'; end if;
  return jsonb_build_object(
    'role',r,
    'loans',coalesce((select jsonb_agg(jsonb_build_object('loan_id',l.id,'title',b.title,'author',b.author,'accession_no',c.accession_no,'student_id',s.id,'student',case when s.id is null then null else concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) end,'issued_at',l.issued_at,'due_date',l.due_date,'returned_at',l.returned_at,'renew_count',l.renew_count,'status',case when l.status='issued' and l.returned_at is null and l.due_date<current_date then 'overdue' else l.status end) order by l.issued_at desc) from public.library_loans l join public.library_copies c on c.id=l.copy_id join public.library_books b on b.id=c.book_id left join public.students s on s.id=l.borrower_student_id left join public.hr_staff_members h on h.id=l.borrower_hr_staff_id where (r='student' and s.profile_id=auth.uid()) or (r='parent_guardian' and s.id is not null and exists(select 1 from public.guardian_links gl where gl.auth_user_id=auth.uid() and gl.student_id=s.id)) or (r not in ('student','parent_guardian') and h.profile_id=auth.uid())),'[]'::jsonb),
    'reservations',coalesce((select jsonb_agg(jsonb_build_object('reservation_id',rv.id,'book_id',b.id,'title',b.title,'author',b.author,'student_id',s.id,'student',case when s.id is null then null else concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) end,'status',rv.status,'reserved_at',rv.reserved_at,'ready_at',rv.ready_at,'expires_at',rv.expires_at) order by rv.reserved_at desc) from public.library_reservations rv join public.library_books b on b.id=rv.book_id left join public.students s on s.id=rv.borrower_student_id left join public.hr_staff_members h on h.id=rv.borrower_hr_staff_id where (r='student' and s.profile_id=auth.uid()) or (r='parent_guardian' and s.id is not null and exists(select 1 from public.guardian_links gl where gl.auth_user_id=auth.uid() and gl.student_id=s.id)) or (r not in ('student','parent_guardian') and h.profile_id=auth.uid())),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.library_place_my_reservation(target_book_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r text; v_license jsonb; v_student uuid; v_staff uuid; v_row public.library_reservations;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Library reservations are unavailable while the school licence is read-only' using errcode='42501'; end if;
  if not exists(select 1 from public.library_books where id=target_book_id and deleted_at is null and active) then raise exception 'Library title not found'; end if;
  r:=public.current_app_role()::text;
  if r='student' then
    select id into v_student from public.students where profile_id=auth.uid() and deleted_at is null;
    if v_student is null then raise exception 'Active student borrower not found'; end if;
    insert into public.library_reservations(book_id,borrower_type,borrower_student_id,created_by) values(target_book_id,'student',v_student,auth.uid()) returning * into v_row;
  elsif r not in ('parent_guardian','platform_super_admin') then
    select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and deleted_at is null and active;
    if v_staff is null then raise exception 'Active staff borrower not found'; end if;
    insert into public.library_reservations(book_id,borrower_type,borrower_hr_staff_id,created_by) values(target_book_id,'staff',v_staff,auth.uid()) returning * into v_row;
  else raise exception 'This role cannot place a personal reservation' using errcode='42501'; end if;
  return to_jsonb(v_row);
exception when unique_violation then raise exception 'An active reservation already exists for this title';
end $function$

CREATE OR REPLACE FUNCTION public.library_public_catalog(search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Library catalog unavailable while school licence is locked' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'isbn',b.isbn,'title',b.title,'author',b.author,'publisher',b.publisher,'publication_year',b.publication_year,'category',b.category,'subject',b.subject,'language',b.language,'available',(select count(*) from public.library_copies c where c.book_id=b.id and c.deleted_at is null and c.active and c.circulation_status='available'),'total',(select count(*) from public.library_copies c where c.book_id=b.id and c.deleted_at is null and c.active)) order by b.title,b.author) from public.library_books b where b.deleted_at is null and b.active and (coalesce(nullif(search_text,''),'')='' or b.title ilike '%'||search_text||'%' or b.author ilike '%'||search_text||'%' or coalesce(b.isbn,'') ilike '%'||search_text||'%')),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.library_record_copy_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='INSERT' then
    insert into public.library_inventory_events(copy_id,event_type,details,actor_id) values(new.id,'copy_created',jsonb_build_object('accession_no',new.accession_no,'status',new.circulation_status),coalesce(auth.uid(),new.created_by));
  elsif tg_op='UPDATE' then
    if old.circulation_status is distinct from new.circulation_status or old.condition_status is distinct from new.condition_status then
      insert into public.library_inventory_events(copy_id,event_type,details,actor_id) values(new.id,'copy_status_changed',jsonb_build_object('circulation_from',old.circulation_status,'circulation_to',new.circulation_status,'condition_from',old.condition_status,'condition_to',new.condition_status),auth.uid());
    end if;
  end if;
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.library_renew_loan(target_loan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_loan public.library_loans; v_settings public.library_settings; v_book uuid;
begin
  perform public.library_require_access(true,'circulate');
  select * into v_loan from public.library_loans where id=target_loan_id and status='issued' and returned_at is null for update;
  if v_loan.id is null then raise exception 'Active library loan not found'; end if;
  select * into v_settings from public.library_settings limit 1;
  if v_loan.renew_count>=v_settings.max_renewals then raise exception 'Maximum renewals reached'; end if;
  select book_id into v_book from public.library_copies where id=v_loan.copy_id;
  if exists(select 1 from public.library_reservations where book_id=v_book and status in ('waiting','ready') and not ((v_loan.borrower_type='student' and borrower_student_id=v_loan.borrower_student_id) or (v_loan.borrower_type='staff' and borrower_hr_staff_id=v_loan.borrower_hr_staff_id))) then raise exception 'Loan cannot be renewed because another borrower is waiting'; end if;
  update public.library_loans set due_date=greatest(due_date,current_date)+v_settings.renewal_days,renew_count=renew_count+1 where id=v_loan.id returning * into v_loan;
  return to_jsonb(v_loan);
end $function$

SET check_function_bodies=on;
