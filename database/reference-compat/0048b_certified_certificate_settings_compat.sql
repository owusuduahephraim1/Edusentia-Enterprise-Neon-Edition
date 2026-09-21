begin;

alter table public.school_settings
  add column if not exists certificate_completion_class_id uuid;

alter table public.school_settings
  add column if not exists certificate_footer_text text
    not null default 'Issued under the authority of the school administration.'::text;

do $certificate_settings$
begin
  if not exists(
    select 1
    from pg_constraint
    where conname='school_settings_certificate_completion_class_id_fkey'
      and conrelid='public.school_settings'::regclass
  ) then
    alter table public.school_settings
      add constraint school_settings_certificate_completion_class_id_fkey
      foreign key(certificate_completion_class_id)
      references public.classes(id)
      on delete set null;
  end if;
end
$certificate_settings$;

insert into app.schema_migrations(version)
values ('0048b_certified_certificate_settings_compat')
on conflict do nothing;

-- 0048b is a compatibility hotfix within certified release 0048.
update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
