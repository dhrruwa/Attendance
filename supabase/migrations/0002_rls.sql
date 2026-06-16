-- =====================================================================
-- 0002_rls.sql — Row Level Security
-- =====================================================================
-- Principles:
--  * A student may INSERT only their own pending (flagged) attendance row and
--    may read ONLY their own attendance rows.
--  * A teacher may read attendance rows for THEIR OWN sessions only, and may
--    update them (flag review).
--  * session_tokens are NEVER readable by students from the DB (they receive
--    tokens over BLE). Only the owning teacher can read them.
--  * The validate_attendance edge function uses the service role and therefore
--    BYPASSES RLS to write the authoritative final decision.
-- =====================================================================

-- Helper functions (security definer, so they can read tables without being
-- blocked by the very RLS they support).
create or replace function public.uid() returns uuid
  language sql stable as $$ select auth.uid() $$;

create or replace function public.owns_session(p_session uuid)
  returns boolean language sql security definer stable
  set search_path = public as $$
    select exists (
      select 1 from sessions s
      where s.id = p_session and s.teacher_id = auth.uid()
    );
$$;

create or replace function public.is_enrolled(p_course uuid)
  returns boolean language sql security definer stable
  set search_path = public as $$
    select exists (
      select 1 from enrollments e
      where e.course_id = p_course and e.student_id = auth.uid()
    );
$$;

create or replace function public.teaches_student(p_student uuid)
  returns boolean language sql security definer stable
  set search_path = public as $$
    select exists (
      select 1
      from enrollments e
      join courses c on c.id = e.course_id
      where e.student_id = p_student and c.teacher_id = auth.uid()
    );
$$;

-- Enable RLS everywhere.
alter table public.institutions   enable row level security;
alter table public.users          enable row level security;
alter table public.courses        enable row level security;
alter table public.enrollments    enable row level security;
alter table public.devices        enable row level security;
alter table public.sessions       enable row level security;
alter table public.session_tokens enable row level security;
alter table public.attendance     enable row level security;

-- ---- institutions ---------------------------------------------------
drop policy if exists institutions_read on public.institutions;
create policy institutions_read on public.institutions
  for select to authenticated
  using (
    id = (select institution_id from public.users where id = auth.uid())
  );

-- ---- users ----------------------------------------------------------
-- Read own profile; teachers may also read profiles of students they teach
-- (needed for the roster to show names).
drop policy if exists users_read_self on public.users;
create policy users_read_self on public.users
  for select to authenticated
  using (id = auth.uid() or public.teaches_student(id));

-- A user may update only their own profile (non-privileged fields).
drop policy if exists users_update_self on public.users;
create policy users_update_self on public.users
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---- courses --------------------------------------------------------
drop policy if exists courses_teacher on public.courses;
create policy courses_teacher on public.courses
  for select to authenticated
  using (teacher_id = auth.uid() or public.is_enrolled(id));

-- ---- enrollments ----------------------------------------------------
drop policy if exists enrollments_read on public.enrollments;
create policy enrollments_read on public.enrollments
  for select to authenticated
  using (student_id = auth.uid() or
         exists (select 1 from courses c
                 where c.id = course_id and c.teacher_id = auth.uid()));

-- ---- devices --------------------------------------------------------
drop policy if exists devices_owner_all on public.devices;
create policy devices_owner_all on public.devices
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---- sessions -------------------------------------------------------
-- Teacher: full control of own sessions. Student: read sessions for courses
-- they're enrolled in (to confirm session id discovered over BLE).
drop policy if exists sessions_teacher_all on public.sessions;
create policy sessions_teacher_all on public.sessions
  for all to authenticated
  using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());

drop policy if exists sessions_student_read on public.sessions;
create policy sessions_student_read on public.sessions
  for select to authenticated
  using (public.is_enrolled(course_id));

-- ---- session_tokens -------------------------------------------------
-- Only the owning teacher may read/manage tokens. Students get tokens over BLE,
-- NEVER from the DB — so there is no student select policy (default deny).
drop policy if exists session_tokens_teacher on public.session_tokens;
create policy session_tokens_teacher on public.session_tokens
  for all to authenticated
  using (public.owns_session(session_id))
  with check (public.owns_session(session_id));

-- ---- attendance -----------------------------------------------------
-- Student: read ONLY own rows.
drop policy if exists attendance_student_read on public.attendance;
create policy attendance_student_read on public.attendance
  for select to authenticated
  using (student_id = auth.uid());

-- Student: INSERT only own row, and only as pending ('flagged'). The final
-- present/flagged/absent decision is made server-side (service role) — students
-- can never insert a 'present' row themselves.
drop policy if exists attendance_student_insert on public.attendance;
create policy attendance_student_insert on public.attendance
  for insert to authenticated
  with check (student_id = auth.uid() and status = 'flagged');

-- Teacher: read + update attendance for OWN sessions only (flag review).
drop policy if exists attendance_teacher_read on public.attendance;
create policy attendance_teacher_read on public.attendance
  for select to authenticated
  using (public.owns_session(session_id));

drop policy if exists attendance_teacher_update on public.attendance;
create policy attendance_teacher_update on public.attendance
  for update to authenticated
  using (public.owns_session(session_id))
  with check (public.owns_session(session_id));
