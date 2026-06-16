-- =====================================================================
-- seed.sql — demo institution, courses, and a teacher/student linkage.
-- =====================================================================
-- NOTE: public.users.id must reference an existing auth.users row. Create the
-- auth users first (Dashboard > Authentication > Add user, or the snippet in the
-- README using the Admin API), grab their UUIDs, and paste them below before
-- running this seed. The placeholder UUIDs here will FAIL the FK unless they
-- match real auth users.
-- =====================================================================

-- 1) Institution
insert into public.institutions (id, name)
values ('00000000-0000-0000-0000-0000000000a1', 'Demo University')
on conflict (id) do nothing;

-- 2) Users — replace the two UUIDs with real auth.users ids.
--    Teacher:
insert into public.users (id, institution_id, role, full_name, teacher_code)
values (
  '11111111-1111-1111-1111-111111111111',         -- <- real auth uid (teacher)
  '00000000-0000-0000-0000-0000000000a1',
  'teacher', 'Prof. Ada Lovelace', 'TEACH-001'
) on conflict (id) do nothing;

--    Student:
insert into public.users (id, institution_id, role, full_name, student_code)
values (
  '22222222-2222-2222-2222-222222222222',         -- <- real auth uid (student)
  '00000000-0000-0000-0000-0000000000a1',
  'student', 'Grace Hopper', 'STU-1001'
) on conflict (id) do nothing;

-- 3) Course owned by the teacher
insert into public.courses (id, institution_id, teacher_id, name, code)
values (
  '00000000-0000-0000-0000-0000000000c1',
  '00000000-0000-0000-0000-0000000000a1',
  '11111111-1111-1111-1111-111111111111',
  'Intro to Computing', 'CS101'
) on conflict (id) do nothing;

-- 4) Enroll the student
insert into public.enrollments (course_id, student_id)
values (
  '00000000-0000-0000-0000-0000000000c1',
  '22222222-2222-2222-2222-222222222222'
) on conflict (course_id, student_id) do nothing;
