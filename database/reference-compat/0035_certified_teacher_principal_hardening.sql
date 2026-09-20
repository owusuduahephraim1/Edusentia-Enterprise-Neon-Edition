-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source blob SHA: 7d5dd04890d26fc2fe27a9857dd485d9861ffe1c
-- Neon adaptation: SQL ACL targets only. Business authorization logic is unchanged.

-- Edusentia Enterprise r40 — Teacher & Principal Management hardening
--
-- Requires System Administrator + AAL2 for staff-record management and enforces
-- a single current active Principal appointment. No staff record is modified by
-- this migration beyond the authorization/schema rules themselves.

create or replace function public.can_manage_teachers()
returns boolean
language sql
stable
security definer
set search_path to 'public','extensions'
as $$
  select public.is_system_admin() and public.current_aal()='aal2'
$$;

create or replace function public.can_manage_headteachers()
returns boolean
language sql
stable
security definer
set search_path to 'public','extensions'
as $$
  select public.is_system_admin() and public.current_aal()='aal2'
$$;

create or replace function public.enforce_single_current_principal()
returns trigger
language plpgsql
set search_path to 'public','extensions'
as $$
begin
  if new.deleted_at is null and new.active and new.employment_status='active' then
    if exists(
      select 1
      from public.headteachers h
      where h.deleted_at is null
        and h.active
        and h.employment_status='active'
        and h.id<>new.id
    ) then
      raise exception 'Another active Principal appointment already exists';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists headteachers_single_current_guard on public.headteachers;
create trigger headteachers_single_current_guard
before insert or update of active,employment_status,deleted_at on public.headteachers
for each row execute function public.enforce_single_current_principal();

create unique index if not exists headteachers_one_current_principal_idx
on public.headteachers ((1))
where deleted_at is null and active and employment_status='active';

revoke all on function public.enforce_single_current_principal() from public,edusentia_worker_runtime;


revoke all on function public.can_manage_teachers() from public;
revoke all on function public.can_manage_headteachers() from public;
revoke all on function public.enforce_single_current_principal() from public;
revoke all on function public.can_manage_teachers() from edusentia_worker_runtime;
revoke all on function public.can_manage_headteachers() from edusentia_worker_runtime;
revoke all on function public.enforce_single_current_principal() from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0035_certified_teacher_principal_hardening')
on conflict do nothing;

update app.release_identity
set schema_version='0035'
where edition='Edusentia Enterprise Neon Edition';
