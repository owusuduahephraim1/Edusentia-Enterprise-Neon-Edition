begin;

create table public.communication_templates (
 id uuid primary key default gen_random_uuid(),
 template_name text not null unique,
 subject_template text,
 body_template text not null,
 category text not null default 'general',
 active boolean not null default true,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.communication_campaigns (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 body text not null,
 category text not null default 'general',
 audience_type text not null check(audience_type in ('all_staff','all_students','all_guardians','class_students','class_guardians','selected_profiles')),
 audience_class_id uuid references public.classes(id) on delete restrict,
 audience_profile_ids uuid[] not null default '{}',
 channels text[] not null default array['in_app']::text[],
 status text not null default 'draft' check(status in ('draft','scheduled','published','cancelled')),
 scheduled_at timestamptz,
 published_at timestamptz,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(channels <@ array['in_app','email','sms','push']::text[] and cardinality(channels)>0),
 check((audience_type in ('class_students','class_guardians') and audience_class_id is not null) or audience_type not in ('class_students','class_guardians'))
);

create table public.communication_deliveries (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.communication_campaigns(id) on delete restrict,
 recipient_profile_id uuid references public.profiles(id) on delete set null,
 student_id uuid references public.students(id) on delete set null,
 recipient_name text,
 recipient_email text,
 recipient_phone text,
 channel text not null check(channel in ('in_app','email','sms','push')),
 status text not null default 'queued' check(status in ('queued','sent','failed','skipped')),
 outbox_id uuid references public.notification_outbox(id) on delete set null,
 queued_at timestamptz not null default now(),
 sent_at timestamptz,
 error_message text,
 created_at timestamptz not null default now()
);

create table public.communication_threads (
 id uuid primary key default gen_random_uuid(),
 subject text not null,
 status text not null default 'open' check(status in ('open','closed','archived')),
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.communication_thread_participants (
 id uuid primary key default gen_random_uuid(),
 thread_id uuid not null references public.communication_threads(id) on delete restrict,
 profile_id uuid not null references public.profiles(id) on delete restrict,
 participant_role text not null default 'member' check(participant_role in ('owner','member')),
 joined_at timestamptz not null default now(),
 last_read_at timestamptz,
 unique(thread_id,profile_id)
);

create table public.communication_messages (
 id uuid primary key default gen_random_uuid(),
 thread_id uuid not null references public.communication_threads(id) on delete restrict,
 sender_profile_id uuid references public.profiles(id) on delete set null,
 body text not null,
 created_at timestamptz not null default now(),
 edited_at timestamptz
);

create index communication_campaign_status_idx on public.communication_campaigns(status,scheduled_at,created_at desc);
create index communication_campaign_created_by_idx on public.communication_campaigns(created_by);
create index communication_delivery_campaign_idx on public.communication_deliveries(campaign_id,status,channel);
create index communication_delivery_profile_idx on public.communication_deliveries(recipient_profile_id,created_at desc);
create index communication_delivery_student_idx on public.communication_deliveries(student_id,created_at desc);
create index communication_delivery_outbox_idx on public.communication_deliveries(outbox_id) where outbox_id is not null;
create index communication_thread_created_by_idx on public.communication_threads(created_by);
create index communication_participant_profile_idx on public.communication_thread_participants(profile_id,thread_id);
create index communication_message_thread_idx on public.communication_messages(thread_id,created_at);
create index communication_message_sender_idx on public.communication_messages(sender_profile_id,created_at desc);
create index communication_template_created_by_idx on public.communication_templates(created_by);

alter table public.communication_templates enable row level security;
alter table public.communication_campaigns enable row level security;
alter table public.communication_deliveries enable row level security;
alter table public.communication_threads enable row level security;
alter table public.communication_thread_participants enable row level security;
alter table public.communication_messages enable row level security;
revoke all on table public.communication_templates,public.communication_campaigns,public.communication_deliveries,public.communication_threads,public.communication_thread_participants,public.communication_messages from public,anon,authenticated;
grant all on table public.communication_templates,public.communication_campaigns,public.communication_deliveries,public.communication_threads,public.communication_thread_participants,public.communication_messages to service_role;

create trigger communication_template_touch before update on public.communication_templates for each row execute function public.student_services_touch_updated_at();
create trigger communication_campaign_touch before update on public.communication_campaigns for each row execute function public.student_services_touch_updated_at();
create trigger communication_thread_touch before update on public.communication_threads for each row execute function public.student_services_touch_updated_at();
create trigger communication_template_audit after insert or update or delete on public.communication_templates for each row execute function public.audit_row_change();
create trigger communication_campaign_audit after insert or update or delete on public.communication_campaigns for each row execute function public.audit_row_change();
create trigger communication_delivery_audit after insert or update or delete on public.communication_deliveries for each row execute function public.audit_row_change();
create trigger communication_thread_audit after insert or update or delete on public.communication_threads for each row execute function public.audit_row_change();
create trigger communication_message_audit after insert or update or delete on public.communication_messages for each row execute function public.audit_row_change();
create trigger communication_template_no_delete before delete on public.communication_templates for each row execute function public.student_services_block_delete();
create trigger communication_campaign_no_delete before delete on public.communication_campaigns for each row execute function public.student_services_block_delete();
create trigger communication_delivery_no_delete before delete on public.communication_deliveries for each row execute function public.student_services_block_delete();
create trigger communication_thread_no_delete before delete on public.communication_threads for each row execute function public.student_services_block_delete();
create trigger communication_participant_no_delete before delete on public.communication_thread_participants for each row execute function public.student_services_block_delete();
create trigger communication_message_no_delete before delete on public.communication_messages for each row execute function public.student_services_block_delete();

create or replace function public.communications_dashboard()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('communications','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'draft_campaigns',(select count(*) from public.communication_campaigns where status='draft'),
  'scheduled_campaigns',(select count(*) from public.communication_campaigns where status='scheduled'),
  'published_30_days',(select count(*) from public.communication_campaigns where status='published' and published_at>=now()-interval '30 days'),
  'queued_deliveries',(select count(*) from public.communication_deliveries where status='queued'),
  'failed_deliveries',(select count(*) from public.communication_deliveries where status='failed'),
  'open_threads',(select count(*) from public.communication_threads where status='open')
 ));
end $$;

create or replace function public.communications_campaign_options()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('communications','read');
 return jsonb_build_object(
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.active and c.deleted_at is null),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'template_name',t.template_name,'subject_template',t.subject_template,'body_template',t.body_template,'category',t.category) order by t.template_name) from public.communication_templates t where t.active),'[]'::jsonb)
 );
end $$;

create or replace function public.communications_campaign_register(status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('communications','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
  select c.id,c.title,c.category,c.audience_type,c.audience_class_id,cl.name class_name,c.channels,c.status,c.scheduled_at,c.published_at,c.created_at,
   (select count(*) from public.communication_deliveries d where d.campaign_id=c.id) delivery_count,
   (select count(*) from public.communication_deliveries d where d.campaign_id=c.id and d.status='failed') failed_count
  from public.communication_campaigns c left join public.classes cl on cl.id=c.audience_class_id
  where status_filter is null or c.status=status_filter
 )q),'[]'::jsonb);
end $$;

create or replace function public.communications_save_template(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('communications','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.communication_templates(template_name,subject_template,body_template,category,active,created_by) values(btrim(payload->>'template_name'),nullif(payload->>'subject_template',''),btrim(payload->>'body_template'),coalesce(nullif(payload->>'category',''),'general'),coalesce((payload->>'active')::boolean,true),auth.uid()) returning id into v_id;
 else update public.communication_templates set template_name=coalesce(nullif(btrim(payload->>'template_name'),''),template_name),subject_template=case when payload ? 'subject_template' then nullif(payload->>'subject_template','') else subject_template end,body_template=coalesce(nullif(btrim(payload->>'body_template'),''),body_template),category=coalesce(nullif(payload->>'category',''),category),active=coalesce((payload->>'active')::boolean,active) where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.communications_save_campaign(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;v_channels text[];v_profiles uuid[];
begin
 perform public.student_services_require_access('communications','write');
 v_id:=nullif(payload->>'id','')::uuid;
 select coalesce(array_agg(value),array['in_app']::text[]) into v_channels from jsonb_array_elements_text(coalesce(payload->'channels','["in_app"]'::jsonb));
 select coalesce(array_agg(value::uuid),array[]::uuid[]) into v_profiles from jsonb_array_elements_text(coalesce(payload->'audience_profile_ids','[]'::jsonb));
 if v_id is null then insert into public.communication_campaigns(title,body,category,audience_type,audience_class_id,audience_profile_ids,channels,status,scheduled_at,created_by) values(btrim(payload->>'title'),btrim(payload->>'body'),coalesce(nullif(payload->>'category',''),'general'),payload->>'audience_type',nullif(payload->>'audience_class_id','')::uuid,v_profiles,v_channels,coalesce(nullif(payload->>'status',''),'draft'),nullif(payload->>'scheduled_at','')::timestamptz,auth.uid()) returning id into v_id;
 else update public.communication_campaigns set title=coalesce(nullif(btrim(payload->>'title'),''),title),body=coalesce(nullif(btrim(payload->>'body'),''),body),category=coalesce(nullif(payload->>'category',''),category),audience_type=coalesce(nullif(payload->>'audience_type',''),audience_type),audience_class_id=case when payload ? 'audience_class_id' then nullif(payload->>'audience_class_id','')::uuid else audience_class_id end,audience_profile_ids=case when payload ? 'audience_profile_ids' then v_profiles else audience_profile_ids end,channels=case when payload ? 'channels' then v_channels else channels end,scheduled_at=case when payload ? 'scheduled_at' then nullif(payload->>'scheduled_at','')::timestamptz else scheduled_at end where id=v_id and status in ('draft','scheduled');
 end if; return v_id;
end $$;

create or replace function public.communications_publish_campaign(target_campaign_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare c public.communication_campaigns%rowtype;ch text;r record;v_delivery uuid;v_outbox uuid;v_count integer:=0;
begin
 perform public.student_services_require_access('communications','publish');
 select * into c from public.communication_campaigns where id=target_campaign_id for update;
 if c.id is null or c.status not in ('draft','scheduled') then raise exception 'Campaign is not publishable'; end if;
 delete from public.communication_deliveries where campaign_id=c.id and status='queued';
 for r in
  with targets as (
   select distinct p.id profile_id,null::uuid student_id,p.full_name recipient_name,null::text recipient_email,p.phone recipient_phone
   from public.profiles p where c.audience_type='selected_profiles' and p.id=any(c.audience_profile_ids) and p.active
   union all
   select distinct h.profile_id,null::uuid,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),h.email,h.phone from public.hr_staff_members h where c.audience_type='all_staff' and h.active and h.deleted_at is null and h.profile_id is not null
   union all
   select distinct s.profile_id,s.id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),nullif(s.guardian_email,''),nullif(s.guardian_phone,'') from public.students s where c.audience_type='all_students' and s.deleted_at is null and s.status='active' and s.profile_id is not null
   union all
   select distinct g.auth_user_id,s.id,coalesce(p.full_name,s.guardian_name),nullif(s.guardian_email,''),coalesce(nullif(p.phone,''),nullif(s.guardian_phone,'')) from public.guardian_links g join public.students s on s.id=g.student_id left join public.profiles p on p.id=g.auth_user_id where c.audience_type='all_guardians' and g.auth_user_id is not null and g.can_receive_notifications
   union all
   select distinct s.profile_id,s.id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),nullif(s.guardian_email,''),nullif(s.guardian_phone,'') from public.enrollments e join public.students s on s.id=e.student_id where c.audience_type='class_students' and e.class_id=c.audience_class_id and e.active and e.deleted_at is null and s.profile_id is not null
   union all
   select distinct g.auth_user_id,s.id,coalesce(p.full_name,s.guardian_name),nullif(s.guardian_email,''),coalesce(nullif(p.phone,''),nullif(s.guardian_phone,'')) from public.enrollments e join public.students s on s.id=e.student_id join public.guardian_links g on g.student_id=s.id left join public.profiles p on p.id=g.auth_user_id where c.audience_type='class_guardians' and e.class_id=c.audience_class_id and e.active and e.deleted_at is null and g.auth_user_id is not null and g.can_receive_notifications
  ) select * from targets
 loop
  foreach ch in array c.channels loop
   if ch='in_app' and r.profile_id is not null then
    insert into public.notifications(recipient_id,title,body,category,entity_type,entity_id) values(r.profile_id,c.title,c.body,c.category,'communication_campaign',c.id);
    insert into public.communication_deliveries(campaign_id,recipient_profile_id,student_id,recipient_name,recipient_email,recipient_phone,channel,status,sent_at) values(c.id,r.profile_id,r.student_id,r.recipient_name,r.recipient_email,r.recipient_phone,ch,'sent',now()) returning id into v_delivery;
    v_count:=v_count+1;
   elsif ch in ('email','sms','push') then
    if (ch='email' and coalesce(r.recipient_email,'')='') or (ch='sms' and coalesce(r.recipient_phone,'')='') or (ch='push' and r.profile_id is null) then
      insert into public.communication_deliveries(campaign_id,recipient_profile_id,student_id,recipient_name,recipient_email,recipient_phone,channel,status,error_message) values(c.id,r.profile_id,r.student_id,r.recipient_name,r.recipient_email,r.recipient_phone,ch,'skipped','Recipient channel unavailable');
    else
      insert into public.notification_outbox(recipient_id,recipient_email,channel,template_key,payload) values(r.profile_id,case when ch='email' then r.recipient_email else null end,ch,'student_services_campaign',jsonb_build_object('title',c.title,'body',c.body,'category',c.category,'campaign_id',c.id,'recipient_phone',r.recipient_phone)) returning id into v_outbox;
      insert into public.communication_deliveries(campaign_id,recipient_profile_id,student_id,recipient_name,recipient_email,recipient_phone,channel,status,outbox_id) values(c.id,r.profile_id,r.student_id,r.recipient_name,r.recipient_email,r.recipient_phone,ch,'queued',v_outbox);
      v_count:=v_count+1;
    end if;
   end if;
  end loop;
 end loop;
 update public.communication_campaigns set status='published',published_at=now() where id=c.id;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('communications','campaign_published','communication_campaign',c.id,auth.uid(),jsonb_build_object('queued_or_sent',v_count));
 return jsonb_build_object('campaign_id',c.id,'queued_or_sent',v_count);
end $$;

create or replace function public.communications_delivery_register(target_campaign_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('communications','read');
 return coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from public.communication_deliveries d where d.campaign_id=target_campaign_id),'[]'::jsonb);
end $$;

create or replace function public.communications_create_thread(subject_text text,participant_profile_ids uuid[])
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;p uuid;
begin
 perform public.student_services_require_access('communications','write');
 if participant_profile_ids is null or cardinality(participant_profile_ids)=0 then raise exception 'Select at least one participant'; end if;
 insert into public.communication_threads(subject,created_by) values(btrim(subject_text),auth.uid()) returning id into v_id;
 insert into public.communication_thread_participants(thread_id,profile_id,participant_role) values(v_id,auth.uid(),'owner') on conflict do nothing;
 foreach p in array participant_profile_ids loop insert into public.communication_thread_participants(thread_id,profile_id,participant_role) select v_id,p,'member' where exists(select 1 from public.profiles x where x.id=p and x.active) on conflict do nothing; end loop;
 return v_id;
end $$;

create or replace function public.communications_send_message(target_thread_id uuid,message_body text)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.communication_thread_participants p join public.communication_threads t on t.id=p.thread_id where p.thread_id=target_thread_id and p.profile_id=auth.uid() and t.status='open') then raise exception 'Thread access denied' using errcode='42501'; end if;
 insert into public.communication_messages(thread_id,sender_profile_id,body) values(target_thread_id,auth.uid(),btrim(message_body)) returning id into v_id;
 return v_id;
end $$;

create or replace function public.communications_my_threads()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from (
  select t.id,t.subject,t.status,t.updated_at,(select count(*) from public.communication_messages m where m.thread_id=t.id) message_count,
   (select m.body from public.communication_messages m where m.thread_id=t.id order by m.created_at desc limit 1) last_message
  from public.communication_threads t join public.communication_thread_participants p on p.thread_id=t.id where p.profile_id=auth.uid()
 )q),'[]'::jsonb);
end $$;

create or replace function public.communications_thread_messages(target_thread_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.communication_thread_participants where thread_id=target_thread_id and profile_id=auth.uid()) then raise exception 'Thread access denied' using errcode='42501'; end if;
 update public.communication_thread_participants set last_read_at=now() where thread_id=target_thread_id and profile_id=auth.uid();
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at) from (select m.id,m.thread_id,m.sender_profile_id,p.full_name sender_name,m.body,m.created_at,m.edited_at from public.communication_messages m left join public.profiles p on p.id=m.sender_profile_id where m.thread_id=target_thread_id)q),'[]'::jsonb);
end $$;

revoke all on function public.communications_dashboard(),public.communications_campaign_options(),public.communications_campaign_register(text),public.communications_save_template(jsonb),public.communications_save_campaign(jsonb),public.communications_publish_campaign(uuid),public.communications_delivery_register(uuid),public.communications_create_thread(text,uuid[]),public.communications_send_message(uuid,text),public.communications_my_threads(),public.communications_thread_messages(uuid) from public,anon,authenticated;
grant execute on function public.communications_dashboard(),public.communications_campaign_options(),public.communications_campaign_register(text),public.communications_save_template(jsonb),public.communications_save_campaign(jsonb),public.communications_publish_campaign(uuid),public.communications_delivery_register(uuid),public.communications_create_thread(text,uuid[]) to authenticated;
grant execute on function public.communications_send_message(uuid,text),public.communications_my_threads(),public.communications_thread_messages(uuid) to authenticated;

commit;