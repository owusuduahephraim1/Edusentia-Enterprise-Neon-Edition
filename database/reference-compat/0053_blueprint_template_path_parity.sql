-- Align Neon report-card template storage paths with the Supabase blueprint range structure
-- while preserving tenant-scoped R2 object isolation.
begin;

alter table public.report_card_templates
  drop constraint if exists report_card_templates_path_chk;

alter table public.report_card_templates
  add constraint report_card_templates_path_chk
  check (
    storage_path not like '%..%'
    and (
      storage_path like (range_key||'/%')
      or storage_path like ('tenants/%/report-card-templates/'||range_key||'/%')
    )
  );

create or replace function public.save_report_card_template(
  target_range_key text,
  target_storage_path text,
  target_original_name text,
  target_mime_type text,
  target_file_size bigint,
  target_checksum text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','extensions','pg_catalog'
as $function$
declare
  result public.report_card_templates;
  v_tenant_id uuid:=app.current_tenant_id();
  clean_path text:=btrim(coalesce(target_storage_path,''));
  expected_prefix text;
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Authenticated tenant context is required' using errcode='42501';
  end if;
  if target_range_key not in ('early_years','basic_1_6','basic_7_9') then
    raise exception 'Invalid report-card class range' using errcode='22023';
  end if;

  expected_prefix:='tenants/'||v_tenant_id::text||'/report-card-templates/'||target_range_key||'/';
  if clean_path='' or clean_path not like (expected_prefix||'%') or clean_path like '%..%' then
    raise exception 'Invalid template storage path' using errcode='22023';
  end if;
  if coalesce(btrim(target_original_name),'')='' or length(target_original_name)>255 then
    raise exception 'Invalid template file name' using errcode='22023';
  end if;
  if target_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then
    raise exception 'Unsupported template file type' using errcode='22023';
  end if;
  if coalesce(target_file_size,0)<=0 or target_file_size>20971520 then
    raise exception 'Template file must be between 1 byte and 20 MB' using errcode='22023';
  end if;
  if not exists(
    select 1
    from storage.object_metadata m
    where m.tenant_id=v_tenant_id
      and m.object_key=clean_path
      and m.status='active'
      and lower(m.content_type)=lower(target_mime_type)
      and m.size_bytes=target_file_size
  ) then
    raise exception 'The uploaded report-card template is not available in protected storage' using errcode='22023';
  end if;
  if coalesce(length(target_checksum),0)>128 then
    raise exception 'Invalid template checksum' using errcode='22023';
  end if;

  insert into public.report_card_templates(
    range_key,storage_path,original_name,mime_type,file_size,checksum,version,active,uploaded_by
  ) values(
    target_range_key,clean_path,btrim(target_original_name),target_mime_type,target_file_size,coalesce(target_checksum,''),1,true,auth.uid()
  )
  on conflict(range_key) do update set
    storage_path=excluded.storage_path,
    original_name=excluded.original_name,
    mime_type=excluded.mime_type,
    file_size=excluded.file_size,
    checksum=excluded.checksum,
    version=public.report_card_templates.version+1,
    active=true,
    uploaded_by=auth.uid(),
    updated_at=now()
  returning * into result;

  return to_jsonb(result);
end
$function$;

revoke all on function public.save_report_card_template(text,text,text,text,bigint,text) from public;
grant execute on function public.save_report_card_template(text,text,text,text,bigint,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0053_blueprint_template_path_parity')
on conflict do nothing;

commit;
