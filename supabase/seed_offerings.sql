-- Demo seed for the offerings/timetable model. Idempotent-ish (on conflict).
-- inst a1, teacher Ada 4db2903b. Subjects DBMS/OS, sections 6th & 4th sem.

insert into public.subjects(id,code,name) values
 ('00000000-0000-0000-0000-0000000000d1','CS-DBMS','Database Management Systems'),
 ('00000000-0000-0000-0000-0000000000d2','CS-OS','Operating Systems')
on conflict (id) do nothing;

insert into public.sections(id,institution_id,name,semester,dept) values
 ('00000000-0000-0000-0000-0000000056a6','00000000-0000-0000-0000-0000000000a1','CSE-A',6,'CSE'),
 ('00000000-0000-0000-0000-0000000054a4','00000000-0000-0000-0000-0000000000a1','CSE-A',4,'CSE')
on conflict (id) do nothing;

insert into public.offerings(id,institution_id,subject_id,section_id,teacher_id,room) values
 ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000056a6',
  '4db2903b-edfc-41e7-bb5d-ef3a48f13b77','LH-1'),
 ('00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000054a4',
  '4db2903b-edfc-41e7-bb5d-ef3a48f13b77','LH-2')
on conflict (id) do nothing;

-- timetable: both offerings meet TODAY (so the Today view shows them).
insert into public.timetable(offering_id,weekday,start_time,end_time,room)
select '00000000-0000-0000-0000-0000000000f1', extract(isodow from current_date)::int,
       time '09:00', time '10:00', 'LH-1'
where not exists (select 1 from public.timetable where offering_id='00000000-0000-0000-0000-0000000000f1');
insert into public.timetable(offering_id,weekday,start_time,end_time,room)
select '00000000-0000-0000-0000-0000000000f2', extract(isodow from current_date)::int,
       time '11:00', time '12:00', 'LH-2'
where not exists (select 1 from public.timetable where offering_id='00000000-0000-0000-0000-0000000000f2');

-- real students into 6th-sem section.
insert into public.section_students(section_id,student_id) values
 ('00000000-0000-0000-0000-0000000056a6','483462b6-0600-4a99-890b-29715a4ee540'),
 ('00000000-0000-0000-0000-0000000056a6','067eea34-5a27-4c8f-84d7-5590323f25e9')
on conflict do nothing;

-- ===== bulk filler students (no login) so rosters look like ~60 =====
-- deterministic ids per index so auth/users/section_students line up across
-- the three sequential statements.

-- 6th sem: 58 fillers (id prefix 6)
insert into auth.users(instance_id,id,aud,role,email,created_at,updated_at,
                       raw_app_meta_data,raw_user_meta_data,email_confirmed_at)
select '00000000-0000-0000-0000-000000000000',
       ('60000000-0000-0000-0000-'||lpad(g::text,12,'0'))::uuid,
       'authenticated','authenticated','s6_'||lpad(g::text,3,'0')||'@demo.local',
       now(),now(),'{}','{}',now()
from generate_series(1,58) g
on conflict (id) do nothing;

insert into public.users(id,institution_id,role,full_name,student_code)
select ('60000000-0000-0000-0000-'||lpad(g::text,12,'0'))::uuid,
       '00000000-0000-0000-0000-0000000000a1','student',
       'Sem6 Student '||lpad(g::text,3,'0'),'S6-'||lpad(g::text,3,'0')
from generate_series(1,58) g
on conflict (id) do nothing;

insert into public.section_students(section_id,student_id)
select '00000000-0000-0000-0000-0000000056a6',
       ('60000000-0000-0000-0000-'||lpad(g::text,12,'0'))::uuid
from generate_series(1,58) g
on conflict do nothing;

-- 4th sem: 60 fillers (id prefix 4)
insert into auth.users(instance_id,id,aud,role,email,created_at,updated_at,
                       raw_app_meta_data,raw_user_meta_data,email_confirmed_at)
select '00000000-0000-0000-0000-000000000000',
       ('40000000-0000-0000-0000-'||lpad(g::text,12,'0'))::uuid,
       'authenticated','authenticated','s4_'||lpad(g::text,3,'0')||'@demo.local',
       now(),now(),'{}','{}',now()
from generate_series(1,60) g
on conflict (id) do nothing;

insert into public.users(id,institution_id,role,full_name,student_code)
select ('40000000-0000-0000-0000-'||lpad(g::text,12,'0'))::uuid,
       '00000000-0000-0000-0000-0000000000a1','student',
       'Sem4 Student '||lpad(g::text,3,'0'),'S4-'||lpad(g::text,3,'0')
from generate_series(1,60) g
on conflict (id) do nothing;

insert into public.section_students(section_id,student_id)
select '00000000-0000-0000-0000-0000000054a4',
       ('40000000-0000-0000-0000-'||lpad(g::text,12,'0'))::uuid
from generate_series(1,60) g
on conflict do nothing;
