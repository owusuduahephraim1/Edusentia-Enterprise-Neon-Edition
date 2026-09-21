-- Cloudflare Worker notification queue compatibility.
-- Keeps certified queue semantics but limits execution to the Neon Worker role.
begin;

create or replace function public.claim_notification_jobs(
  target_batch_size integer default 50,
  target_worker_id text default null
)
returns setof public.notification_outbox
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare worker text:=coalesce(nullif(btrim(target_worker_id),''),gen_random_uuid()::text);
begin
  if current_user not in ('postgres','service_role','supabase_admin','edusentia_owner') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return query
  with candidates as (
    select o.id
      from public.notification_outbox o
     where o.processed_at is null
       and o.attempts<6
       and o.next_attempt_at<=now()
       and (o.locked_at is null or o.locked_at<now()-interval '15 minutes')
     order by o.created_at
     for update skip locked
     limit least(greatest(coalesce(target_batch_size,50),1),200)
  )
  update public.notification_outbox o
     set locked_at=now(),locked_by=worker
    from candidates c
   where o.id=c.id
  returning o.*;
end
$function$;

create or replace function public.complete_notification_job(
  target_job_id uuid,
  target_worker_id text,
  target_success boolean,
  target_error text default ''
)
returns boolean
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare changed integer;
begin
  if current_user not in ('postgres','service_role','supabase_admin','edusentia_owner') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if target_success then
    update public.notification_outbox
       set processed_at=now(),attempts=attempts+1,last_error='',locked_at=null,locked_by=null
     where id=target_job_id and processed_at is null and locked_by=target_worker_id;
  else
    update public.notification_outbox
       set attempts=attempts+1,
           next_attempt_at=now()+(power(2,least(attempts+1,8))::text||' minutes')::interval,
           last_error=left(coalesce(target_error,''),2000),locked_at=null,locked_by=null
     where id=target_job_id and processed_at is null and locked_by=target_worker_id;
  end if;
  get diagnostics changed=row_count;
  return changed=1;
end
$function$;

revoke all on function public.claim_notification_jobs(integer,text) from public;
revoke all on function public.complete_notification_job(uuid,text,boolean,text) from public;
grant execute on function public.claim_notification_jobs(integer,text) to edusentia_worker_runtime;
grant execute on function public.complete_notification_job(uuid,text,boolean,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0048j_notification_worker_compat')
on conflict do nothing;

commit;
