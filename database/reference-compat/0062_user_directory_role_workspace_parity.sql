-- Production rollout marker: quality gate green before applying directory-role parity.
begin;

-- The certified Supabase Student and Student Portal contracts both bind a
-- student's login profile directly on public.students.profile_id.
alter table public.students
  add column if not exists profile_id uuid references public.profiles(id) on delete set null;

create unique index if not exists students_profile_id_uidx
  on public.students(profile_id)
  where profile_id is not null;

-- Supabase Users & Access stores this state on the school profile and the
-- certified identity bundle reads/writes it for every managed account.
alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

-- Neon production parity repair for directory-linked Users & Access and role workspaces.
-- The certified Supabase implementation exposes active Teacher, Principal, Accounts
-- Office Staff, and Student directory records through list_profiles_with_access().
-- Neon keeps FORCE RLS on sensitive directory tables, so the trusted certified-RPC
-- owner must retain the same internal table visibility that 0048g establishes for
-- the rest of the certified public schema.

do $rls$
declare
  t text;
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_runtime') then
    raise exception 'edusentia_runtime role is required for certified directory parity'
      using errcode='42704';
  end if;

  foreach t in array array[
    'profiles','teachers','headteachers','accounts_office_staff','students',
    'student_guardians','guardian_links','enrollments','classes','subjects',
    'class_subjects','user_class_access'
  ]
  loop
    if to_regclass(format('public.%I',t)) is null then
      continue;
    end if;

    execute format('alter table public.%I enable row level security',t);

    if not exists(
      select 1
      from pg_policies
      where schemaname='public'
        and tablename=t
        and policyname='neon_certified_runtime_owner'
    ) then
      execute format(
        'create policy neon_certified_runtime_owner on public.%I for all to edusentia_runtime using (true) with check (true)',
        t
      );
    end if;
  end loop;
end
$rls$;

create or replace function public.list_profiles_with_access()
returns jsonb
language plpgsql
security definer
set search_path='public','authn','pg_catalog'
as $function$
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  return jsonb_build_object(
    'profiles',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,
        'full_name',p.full_name,
        'email',u.email,
        'role',public.current_app_role_for(p.role),
        'active',p.active,
        'mfa_required',p.mfa_required,
        'must_change_password',p.must_change_password,
        'phone',p.phone,
        'last_seen_at',p.last_seen_at,
        'account_created_at',u.created_at,
        'email_confirmed_at',case when u.id is null then null else u.created_at end,
        'last_sign_in_at',p.last_seen_at,
        'teacher_id',t.id,
        'headteacher_id',h.id,
        'accountant_id',a.id,
        'student_id',s.id,
        'staff_record_id',coalesce(h.id,t.id,a.id,s.id),
        'staff_no',coalesce(h.staff_no::text,t.staff_no::text,a.staff_no::text,s.admission_no::text),
        'access',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',x.id,
            'class_id',x.class_id,
            'class_name',c.name,
            'subject_id',x.subject_id,
            'subject_name',sub.name,
            'access_level',x.access_level
          ) order by lower(c.name),lower(sub.name) nulls first)
          from public.user_class_access x
          join public.classes c on c.id=x.class_id
          left join public.subjects sub on sub.id=x.subject_id
          where x.user_id=p.id
        ),'[]'::jsonb)
      ) order by lower(p.full_name),p.id)
      from public.profiles p
      left join authn.users u on u.id=p.id
      left join public.teachers t on t.profile_id=p.id and t.deleted_at is null
      left join public.headteachers h on h.profile_id=p.id and h.deleted_at is null
      left join public.accounts_office_staff a on a.profile_id=p.id and a.deleted_at is null
      left join public.students s on s.profile_id=p.id and s.deleted_at is null
      where public.current_app_role_for(p.role) in (
        'system_admin','principal','class_teacher','subject_teacher',
        'parent_guardian','accountant','student'
      )
    ),'[]'::jsonb),

    'teacher_records',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',t.id,
        'profile_id',t.profile_id,
        'staff_no',t.staff_no,
        'first_name',t.first_name,
        'middle_name',t.middle_name,
        'last_name',t.last_name,
        'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
        'label',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)||' • '||t.staff_no::text,
        'phone',t.phone,
        'email',t.email,
        'active',t.active
      ) order by lower(concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)),t.staff_no::text)
      from public.teachers t
      where t.deleted_at is null and t.active
    ),'[]'::jsonb),

    'headteacher_records',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',h.id,
        'profile_id',h.profile_id,
        'staff_no',h.staff_no,
        'first_name',h.first_name,
        'middle_name',h.middle_name,
        'last_name',h.last_name,
        'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
        'label',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)||' • '||h.staff_no::text,
        'phone',h.phone,
        'email',h.email,
        'active',h.active
      ) order by lower(concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)),h.staff_no::text)
      from public.headteachers h
      where h.deleted_at is null and h.active
    ),'[]'::jsonb),

    'accountant_records',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,
        'profile_id',a.profile_id,
        'staff_no',a.staff_no,
        'full_name',a.full_name,
        'label',a.full_name||' • '||a.staff_no::text,
        'phone',a.phone,
        'email',a.email,
        'contact_address',a.contact_address,
        'active',a.active
      ) order by lower(a.full_name),a.staff_no::text)
      from public.accounts_office_staff a
      where a.deleted_at is null and a.active
    ),'[]'::jsonb),

    'student_records',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,
        'profile_id',s.profile_id,
        'admission_no',s.admission_no,
        'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'label',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)||' • '||s.admission_no::text,
        'class_id',e.class_id,
        'class_name',c.name,
        'active',s.status='active'
      ) order by c.level_order,s.last_name,s.first_name)
      from public.students s
      left join lateral(
        select x.class_id
        from public.enrollments x
        where x.student_id=s.id
          and x.active
          and x.deleted_at is null
        order by x.updated_at desc
        limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      where s.deleted_at is null and s.status='active'
    ),'[]'::jsonb),

    'classes',coalesce((
      select jsonb_agg(to_jsonb(c) order by c.level_order,c.name)
      from public.classes c
      where c.deleted_at is null
    ),'[]'::jsonb),

    'subjects',coalesce((
      select jsonb_agg(to_jsonb(sub) order by sub.display_order,sub.name)
      from public.subjects sub
      where sub.deleted_at is null
    ),'[]'::jsonb),

    'class_subjects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cs.id,
        'class_id',cs.class_id,
        'subject_id',cs.subject_id,
        'teacher_id',cs.teacher_id,
        'active',cs.active
      ))
      from public.class_subjects cs
    ),'[]'::jsonb)
  );
end
$function$;

revoke all on function public.list_profiles_with_access() from public;
grant execute on function public.list_profiles_with_access() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0062_user_directory_role_workspace_parity')
on conflict do nothing;

commit;
