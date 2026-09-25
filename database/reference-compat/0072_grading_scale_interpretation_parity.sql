-- Neon parity repair: certified save_grading_scale(jsonb) writes the
-- grading_scales.interpretation field, but early Neon tenant schemas omitted it.
-- The certified Supabase behavior treats this as part of the grading-scale record.
begin;

alter table public.grading_scales
  add column if not exists interpretation text;

update public.grading_scales
set interpretation=coalesce(
  nullif(btrim(interpretation),''),
  public.default_grading_interpretation(grade,remark),
  ''
)
where interpretation is null or btrim(interpretation)='';

alter table public.grading_scales
  alter column interpretation set default '';

alter table public.grading_scales
  alter column interpretation set not null;

comment on column public.grading_scales.interpretation
  is 'Certified grading interpretation guide shown in Academic Configuration and report grading guides.';

insert into app.schema_migrations(version)
values ('0072_grading_scale_interpretation_parity')
on conflict do nothing;

commit;
