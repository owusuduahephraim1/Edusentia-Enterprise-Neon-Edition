-- Neon Edition ID-card issuance runtime prerequisites for upgraded isolated tenants.
-- Older tenants can have the card tables/functions without the event tables and
-- card-number sequences that issue_student_id_cards/issue_staff_id_cards require.
begin;

create sequence if not exists public.student_id_card_number_seq
  as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1 no cycle;

create sequence if not exists public.staff_id_card_number_seq
  as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1 no cycle;

create table if not exists public.id_card_events(
  id bigint generated always as identity primary key,
  card_id uuid,
  student_id uuid,
  event_type text not null,
  actor_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.staff_id_card_events(
  id bigint generated always as identity primary key,
  card_id uuid,
  staff_type text not null,
  staff_record_id uuid,
  event_type text not null,
  actor_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

do $constraints$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.id_card_events'::regclass and conname='id_card_events_card_id_fkey') then
    alter table public.id_card_events add constraint id_card_events_card_id_fkey foreign key(card_id) references public.student_id_cards(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.id_card_events'::regclass and conname='id_card_events_student_id_fkey') then
    alter table public.id_card_events add constraint id_card_events_student_id_fkey foreign key(student_id) references public.students(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.id_card_events'::regclass and conname='id_card_events_actor_id_fkey') then
    alter table public.id_card_events add constraint id_card_events_actor_id_fkey foreign key(actor_id) references public.profiles(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.staff_id_card_events'::regclass and conname='staff_id_card_events_card_id_fkey') then
    alter table public.staff_id_card_events add constraint staff_id_card_events_card_id_fkey foreign key(card_id) references public.staff_id_cards(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.staff_id_card_events'::regclass and conname='staff_id_card_events_actor_id_fkey') then
    alter table public.staff_id_card_events add constraint staff_id_card_events_actor_id_fkey foreign key(actor_id) references public.profiles(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.staff_id_card_events'::regclass and conname='staff_id_card_events_staff_type_check') then
    alter table public.staff_id_card_events add constraint staff_id_card_events_staff_type_check check(staff_type in ('teacher','principal'));
  end if;
end
$constraints$;

create index if not exists id_card_events_card_idx on public.id_card_events(card_id,created_at desc);
create index if not exists staff_id_card_events_card_idx on public.staff_id_card_events(card_id,created_at desc);

alter table public.id_card_events enable row level security;
alter table public.staff_id_card_events enable row level security;

do $policies$
begin
  if exists(select 1 from pg_roles where rolname='edusentia_runtime') then
    if not exists(select 1 from pg_policies where schemaname='public' and tablename='id_card_events' and policyname='neon_certified_runtime_owner') then
      create policy neon_certified_runtime_owner on public.id_card_events for all to edusentia_runtime using(true) with check(true);
    end if;
    if not exists(select 1 from pg_policies where schemaname='public' and tablename='staff_id_card_events' and policyname='neon_certified_runtime_owner') then
      create policy neon_certified_runtime_owner on public.staff_id_card_events for all to edusentia_runtime using(true) with check(true);
    end if;
    grant usage,select,update on sequence public.student_id_card_number_seq to edusentia_runtime;
    grant usage,select,update on sequence public.staff_id_card_number_seq to edusentia_runtime;
  end if;
end
$policies$;

do $sync_sequences$
declare n bigint;
begin
  select max(substring(card_number from '-([0-9]+)$')::bigint) into n
  from public.student_id_cards where card_number~'-[0-9]+$';
  if n is not null then perform setval('public.student_id_card_number_seq',greatest(n,1),true); end if;

  select max(substring(card_number from '-([0-9]+)$')::bigint) into n
  from public.staff_id_cards where card_number~'-[0-9]+$';
  if n is not null then perform setval('public.staff_id_card_number_seq',greatest(n,1),true); end if;
end
$sync_sequences$;

insert into app.schema_migrations(version)
values ('0067_id_card_issue_runtime_prerequisites')
on conflict do nothing;

commit;
