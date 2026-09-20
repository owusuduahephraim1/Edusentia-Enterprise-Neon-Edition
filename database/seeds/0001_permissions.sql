insert into app.permissions(code,description) values
('students.read','Read student records'),('students.write','Create and update student records'),('staff.read','Read staff records'),('staff.write','Maintain staff records'),
('academics.read','Read academic records'),('academics.write','Maintain academic records'),('reports.approve','Approve and publish reports'),('finance.read','Read finance records'),('finance.write','Record finance operations'),
('files.read','Read authorized objects'),('files.write','Upload authorized objects'),('admin.users','Manage user access'),('admin.tenant','Manage institution configuration') on conflict(code) do update set description=excluded.description;
insert into app.role_permissions(role,permission_code)
select 'system_admin',code from app.permissions on conflict do nothing;
insert into app.role_permissions(role,permission_code) values
('principal','students.read'),('principal','staff.read'),('principal','academics.read'),('principal','academics.write'),('principal','reports.approve'),('principal','finance.read'),
('academic_admin','students.read'),('academic_admin','students.write'),('academic_admin','academics.read'),('academic_admin','academics.write'),
('class_teacher','students.read'),('class_teacher','academics.read'),('class_teacher','academics.write'),
('subject_teacher','students.read'),('subject_teacher','academics.read'),('subject_teacher','academics.write'),
('records_officer','students.read'),('records_officer','students.write'),('records_officer','academics.read'),
('accountant','students.read'),('accountant','finance.read'),('accountant','finance.write'),
('parent_guardian','students.read'),('student','students.read') on conflict do nothing;
