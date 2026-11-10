-- Share three-digit student admission sequences across each school division.
-- Basic classes share BS, Kindergarten classes share KG, and Nursery classes share NS.
-- Existing admission numbers are intentionally preserved.
begin;

create or replace function public.student_class_identifier_prefix(target_class_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public','pg_catalog'
as $function$
declare
  class_name text;
  prefix text;
begin
  select upper(regexp_replace(btrim(c.name::text),'[[:space:]]+',' ','g'))
  into class_name
  from public.classes c
  where c.id=target_class_id
    and c.deleted_at is null
    and c.active;

  if class_name is null then
    raise exception 'An active class is required to generate the admission number';
  end if;

  if class_name ~ '^BASIC[[:space:]]*[0-9]+[A-Z]?$' then
    prefix:='BS';
  elsif class_name ~ '^KINDERGARTEN[[:space:]]*KG[[:space:]]*[0-9]+[A-Z]?$'
     or class_name ~ '^KINDERGARTEN[[:space:]]*[0-9]+[A-Z]?$'
     or class_name ~ '^KG[[:space:]]*[0-9]+[A-Z]?$' then
    prefix:='KG';
  elsif class_name ~ '^NURSERY[[:space:]]*[0-9]+[A-Z]?$' then
    prefix:='NS';
  elsif class_name in ('CRECHE','CRÈCHE') then
    prefix:='CR';
  else
    prefix:=left(regexp_replace(class_name,'[^A-Z0-9]','','g'),6);
  end if;

  if coalesce(prefix,'')='' then
    raise exception 'A class identifier prefix could not be derived for %',class_name;
  end if;

  return prefix;
end
$function$;

-- Sequence rows remain keyed by class, but the reusable allocator pools
-- numbers by class_prefix. Normalize all active classes to their division key.
update public.student_admission_sequences seq
set class_prefix=public.student_class_identifier_prefix(seq.class_id),
    updated_at=now()
from public.classes c
where c.id=seq.class_id
  and c.deleted_at is null
  and c.active
  and seq.class_prefix is distinct from public.student_class_identifier_prefix(seq.class_id);

insert into app.schema_migrations(version)
values ('0080_shared_division_student_admission_numbers')
on conflict do nothing;

commit;
