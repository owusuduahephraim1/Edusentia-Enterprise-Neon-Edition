begin;

-- Neon identity-management RPCs are invoked by the Cloudflare Worker under
-- edusentia_worker_runtime. Supabase invokes the same routines through a
-- service-role path, so Neon must grant the Worker role explicit EXECUTE
-- permission on the protected validation and apply helpers.

revoke all on function public.admin_validate_user_bundle(uuid,jsonb,boolean) from public;
revoke all on function public.admin_apply_user_bundle(uuid,jsonb) from public;

grant execute on function public.admin_validate_user_bundle(uuid,jsonb,boolean)
  to edusentia_worker_runtime;
grant execute on function public.admin_apply_user_bundle(uuid,jsonb)
  to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0063_identity_user_bundle_runtime_grants')
on conflict do nothing;

commit;
