-- Neon R2 teacher-photograph authorization bridge.
-- Mirrors the certified Supabase teacher-photo authorization rules while
-- keeping the Cloudflare Worker outside the compatibility auth schema.
begin;

create or replace function public.neon_authorize_teacher_photo_upload(target_teacher_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  t public.teachers%rowtype;
begin
  select * into t
  from public.teachers
  where id=target_teacher_id
    and deleted_at is null
  for update;

  if t.id is null then
    raise exception 'Teacher record not found';
  end if;

  if not (public.is_system_admin() or t.profile_id=auth.uid()) then
    raise exception 'Access denied' using errcode='42501';
  end if;

  perform public.require_sensitive_access();

  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes'
      using errcode='42501';
  end if;

  return true;
end
$function$;

create or replace function public.neon_teacher_photo_descriptor(target_teacher_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','extensions'
as $function$
declare
  t public.teachers%rowtype;
begin
  select * into t
  from public.teachers
  where id=target_teacher_id
    and deleted_at is null;

  if t.id is null then
    raise exception 'Teacher record not found';
  end if;

  if not public.can_manage_teachers()
     and t.profile_id is distinct from auth.uid() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  return jsonb_build_object(
    'teacher_id',t.id,
    'photo_url',coalesce(t.photo_url,'')
  );
end
$function$;

revoke all on function public.neon_authorize_teacher_photo_upload(uuid) from public;
revoke all on function public.neon_teacher_photo_descriptor(uuid) from public;
grant execute on function public.neon_authorize_teacher_photo_upload(uuid) to edusentia_worker_runtime;
grant execute on function public.neon_teacher_photo_descriptor(uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0055_teacher_photo_r2_authorization')
on conflict do nothing;

commit;
