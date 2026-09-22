create or replace function public.admin_guardian_account_records()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','auth','extensions'
as $function$
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',sg.id,
        'auth_user_id',linked.auth_user_id,
        'linked_account_count',linked.linked_account_count,
        'portal_email',au.email,
        'full_name',sg.full_name,
        'relationship',sg.relationship,
        'phone',sg.phone,
        'email',sg.email,
        'address',sg.address,
        'is_primary',sg.is_primary,
        'children',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'student_id',s.id,
              'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
              'admission_no',s.admission_no,
              'class_id',ce.class_id,
              'class_name',ce.class_name
            )
            order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text
          )
          from public.guardian_links gl2
          join public.students s on s.id=gl2.student_id and s.deleted_at is null and s.status='active'
          left join lateral (
            select e.class_id,c.name::text as class_name
            from public.enrollments e
            join public.classes c on c.id=e.class_id and c.deleted_at is null
            join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
            where e.student_id=s.id and e.deleted_at is null
            order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
            limit 1
          ) ce on true
          where gl2.guardian_id=sg.id
        ),'[]'::jsonb)
      )
      order by lower(sg.full_name),lower(coalesce(sg.phone,'')),sg.id
    )
    from public.student_guardians sg
    left join lateral (
      select
        min(gl.auth_user_id::text)::uuid as auth_user_id,
        count(distinct gl.auth_user_id)::integer as linked_account_count
      from public.guardian_links gl
      where gl.guardian_id=sg.id and gl.auth_user_id is not null
    ) linked on true
    left join auth.users au on au.id=linked.auth_user_id
    where exists (
      select 1
      from public.guardian_links gl3
      join public.students s3 on s3.id=gl3.student_id and s3.deleted_at is null and s3.status='active'
      where gl3.guardian_id=sg.id
    )
  ),'[]'::jsonb);
end
$function$;

revoke all on function public.admin_guardian_account_records() from public;
revoke all on function public.admin_guardian_account_records() from anon;
grant execute on function public.admin_guardian_account_records() to authenticated;
