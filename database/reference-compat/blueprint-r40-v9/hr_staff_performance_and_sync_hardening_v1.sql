begin;

create index if not exists hr_employment_events_created_by_idx on public.hr_employment_events(created_by) where created_by is not null;
create index if not exists hr_leave_requests_decided_by_idx on public.hr_leave_requests(decided_by) where decided_by is not null;
create index if not exists hr_leave_requests_submitted_by_idx on public.hr_leave_requests(submitted_by) where submitted_by is not null;
create index if not exists hr_staff_documents_created_by_idx on public.hr_staff_documents(created_by) where created_by is not null;
create index if not exists hr_staff_documents_verified_by_idx on public.hr_staff_documents(verified_by) where verified_by is not null;
create index if not exists hr_staff_members_created_by_idx on public.hr_staff_members(created_by) where created_by is not null;
create index if not exists hr_staff_qualifications_created_by_idx on public.hr_staff_qualifications(created_by) where created_by is not null;
create index if not exists hr_staff_qualifications_verified_by_idx on public.hr_staff_qualifications(verified_by) where verified_by is not null;

create or replace function public.hr_sync_staff_from_source()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_catalog','extensions'
as $$
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
    v_type:=case tg_table_name
      when 'teachers' then 'teacher'
      when 'headteachers' then 'principal'
      when 'accounts_office_staff' then 'accounts_office'
      else null
    end;
    if v_type is not null then
      update public.hr_staff_members
      set active=false,
          employment_status='inactive',
          deleted_at=coalesce(deleted_at,now()),
          updated_at=now()
      where source_type=v_type and source_id=old.id;
    end if;
    return old;
  end if;

  if tg_table_name='teachers' then
    v_type:='teacher';
    v_source_id:=new.id;
    v_profile_id:=new.profile_id;
    v_staff_no:=new.staff_no::text;
    v_first:=new.first_name;
    v_middle:=new.middle_name;
    v_last:=new.last_name;
    v_gender:=new.gender;
    v_dob:=new.date_of_birth;
    v_email:=new.email::text;
    v_phone:=new.phone;
    v_address:=new.address;
    v_department:='Academic';
    v_job:='Teacher';
    v_status:=coalesce(new.employment_status,'active');
    v_joined:=new.date_joined;
    v_qualification:=new.qualification;
    v_specialization:=new.specialization;
    v_active:=coalesce(new.active,true);
    v_deleted:=new.deleted_at;
  elsif tg_table_name='headteachers' then
    v_type:='principal';
    v_source_id:=new.id;
    v_profile_id:=new.profile_id;
    v_staff_no:=new.staff_no::text;
    v_first:=new.first_name;
    v_middle:=new.middle_name;
    v_last:=new.last_name;
    v_gender:=new.gender;
    v_dob:=null;
    v_email:=new.email::text;
    v_phone:=new.phone;
    v_address:=new.address;
    v_department:='Leadership';
    v_job:='Principal';
    v_status:=coalesce(new.employment_status,'active');
    v_joined:=new.date_appointed;
    v_qualification:=new.qualification;
    v_specialization:=null;
    v_active:=coalesce(new.active,true);
    v_deleted:=new.deleted_at;
  elsif tg_table_name='accounts_office_staff' then
    v_type:='accounts_office';
    v_source_id:=new.id;
    v_profile_id:=new.profile_id;
    v_staff_no:=new.staff_no::text;
    v_first:=coalesce(nullif(new.full_name,''),'Accounts Office Staff');
    v_middle:=null;
    v_last:='';
    v_gender:=null;
    v_dob:=null;
    v_email:=new.email::text;
    v_phone:=new.phone;
    v_address:=new.contact_address;
    v_department:='Finance';
    v_job:=coalesce(new.job_title,'Accounts Office Staff');
    v_status:=case when coalesce(new.active,true) then 'active' else 'inactive' end;
    v_joined:=null;
    v_qualification:=null;
    v_specialization:=null;
    v_active:=coalesce(new.active,true);
    v_deleted:=new.deleted_at;
  else
    return new;
  end if;

  if coalesce(v_staff_no,'')='' then
    v_staff_no:=public.hr_generate_staff_no();
  end if;

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
end $$;

update public.hr_staff_members
set department=case source_type
      when 'teacher' then 'Academic'
      when 'principal' then 'Leadership'
      when 'accounts_office' then 'Finance'
      else department
    end,
    updated_at=now()
where deleted_at is null
  and coalesce(department,'')=''
  and source_type in ('teacher','principal','accounts_office');

commit;
