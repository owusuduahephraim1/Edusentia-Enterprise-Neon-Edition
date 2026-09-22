create index admissions_applications_applying_class_idx on public.admissions_applications(applying_class_id);
create index admissions_offers_class_idx on public.admissions_offers(class_id);
create index alumni_records_final_class_idx on public.alumni_records(final_class_id);
create index communication_campaigns_audience_class_idx on public.communication_campaigns(audience_class_id);
create index discipline_ack_guardian_user_idx on public.discipline_guardian_acknowledgements(guardian_user_id);
create index student_services_staff_appointed_by_idx on public.student_services_staff_access(appointed_by);

create or replace function public.communications_thread_messages(target_thread_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.communication_thread_participants where thread_id=target_thread_id and profile_id=auth.uid()) then raise exception 'Thread access denied' using errcode='42501'; end if;
 update public.communication_thread_participants set last_read_at=now() where thread_id=target_thread_id and profile_id=auth.uid();
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at) from (select m.id,m.thread_id,m.sender_profile_id,p.full_name sender_name,m.body,m.created_at,m.edited_at from public.communication_messages m left join public.profiles p on p.id=m.sender_profile_id where m.thread_id=target_thread_id)q),'[]'::jsonb);
end $$;
revoke all on function public.communications_thread_messages(uuid) from public,anon,authenticated;
grant execute on function public.communications_thread_messages(uuid) to authenticated;