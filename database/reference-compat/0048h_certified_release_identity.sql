begin;

update app.release_identity
   set schema_version='0048',
       version='neon-v1.0.0-r42',
       api_version='v1',
       frontend_version='neon-v1.0.0-r42',
       worker_version='neon-v1.0.0-r42'
 where edition='Edusentia Enterprise Neon Edition';

insert into app.schema_migrations(version)
values ('0048h_certified_release_identity')
on conflict do nothing;

commit;
