-- AUTO-BUNDLED: paste into Supabase Dashboard > SQL Editor > Run.
-- Source files: supabase/migrations/0001_init.sql + 0002_rls.sql

-- =====================================================================
-- 0001_init.sql — schema for the BLE attendance system
-- =====================================================================
-- All identity flows through Supabase Auth (auth.users). The public.users
-- row mirrors a profile and carries the institution + role + human codes.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---- Enums ----------------------------------------------------------
do $$ begin
  create type user_role as enum ('student', 'teacher');
exception when duplicate_object then null; end $$;

do $$ begin
  create type session_status as enum ('open', 'closed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type attendance_status as enum ('present', 'flagged', 'absent');
exception when duplicate_object then null; end $$;

-- ---- institutions ---------------------------------------------------
create table if not exists public.institutions (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now()
);

-- ---- users (profile mirror of auth.users) ---------------------------
create table if not exists public.users (
  id              uuid primary key references auth.users(id) on delete cascade,
  institution_id  uuid not null references public.institutions(id) on delete restrict,
  role            user_role not null,
  full_name       text not null default '',
  student_code    text unique,
  teacher_code    text unique,
  created_at      timestamptz not null default now(),
  -- a row is either a student (has student_code) or teacher (has teacher_code)
  constraint code_matches_role check (
    (role = 'student'  and student_code is not null and teacher_code is null) or
    (role = 'teacher'  and teacher_code is not null and student_code is null)
  )
);
create index if not exists users_institution_idx on public.users(institution_id);

-- ---- courses --------------------------------------------------------
create table if not exists public.courses (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references public.institutions(id) on delete cascade,
  teacher_id      uuid not null references public.users(id) on delete restrict,
  name            text not null,
  code            text,
  created_at      timestamptz not null default now()
);
create index if not exists courses_teacher_idx on public.courses(teacher_id);

-- ---- enrollments ----------------------------------------------------
create table if not exists public.enrollments (
  id          uuid primary key default gen_random_uuid(),
  course_id   uuid not null references public.courses(id) on delete cascade,
  student_id  uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (course_id, student_id)
);
create index if not exists enrollments_student_idx on public.enrollments(student_id);

-- ---- devices (one active per user) ----------------------------------
create table if not exists public.devices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  device_id   text not null,
  platform    text,
  active      boolean not null default true,
  bound_at    timestamptz not null default now()
);
-- Enforce: at most one ACTIVE device per user.
create unique index if not exists devices_one_active_per_user
  on public.devices(user_id) where (active);
create index if not exists devices_user_idx on public.devices(user_id);

-- ---- sessions -------------------------------------------------------
create table if not exists public.sessions (
  id                  uuid primary key default gen_random_uuid(),
  course_id           uuid not null references public.courses(id) on delete cascade,
  teacher_id          uuid not null references public.users(id) on delete restrict,
  status              session_status not null default 'open',
  started_at          timestamptz not null default now(),
  ends_at             timestamptz not null,
  beacon_service_uuid text not null,
  created_at          timestamptz not null default now()
);
create index if not exists sessions_course_idx on public.sessions(course_id);
create index if not exists sessions_status_idx on public.sessions(status);

-- ---- session_tokens (rotating ~5s) ----------------------------------
create table if not exists public.session_tokens (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.sessions(id) on delete cascade,
  token       text not null,
  valid_from  timestamptz not null,
  valid_to    timestamptz not null
);
create index if not exists session_tokens_session_idx on public.session_tokens(session_id);
create index if not exists session_tokens_window_idx
  on public.session_tokens(session_id, valid_from, valid_to);

-- ---- attendance -----------------------------------------------------
create table if not exists public.attendance (
  id              uuid primary key default gen_random_uuid(),
  session_id      uuid not null references public.sessions(id) on delete cascade,
  student_id      uuid not null references public.users(id) on delete cascade,
  status          attendance_status not null default 'flagged',
  evidence        jsonb not null default '{}'::jsonb,
  submitted_token text,
  rssi            integer,
  device_id       text,
  reason          text,
  created_at      timestamptz not null default now(),
  -- dedupe: one attendance row per student per session
  unique (session_id, student_id)
);
create index if not exists attendance_session_idx on public.attendance(session_id);
create index if not exists attendance_student_idx on public.attendance(student_id);

-- ---- Realtime: stream attendance changes to the teacher roster ------
alter publication supabase_realtime add table public.attendance;

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

-- =====================================================================
-- DEMO SETUP (appended) — confirm the student auth user + seed login data.
-- Safe to re-run. The student auth user was created via the signup API
-- (uuid 483462b6-...); here we just confirm its email and add its profile.
-- =====================================================================

-- 1) Confirm the student's email so password login works regardless of the
--    project's "Confirm email" setting.
update auth.users
   set email_confirmed_at = coalesce(email_confirmed_at, now())
 where id = '483462b6-0600-4a99-890b-29715a4ee540';

-- 2) Institution + student profile (this is all that login needs).
insert into public.institutions (id, name)
values ('00000000-0000-0000-0000-0000000000a1', 'Demo University')
on conflict (id) do nothing;

insert into public.users (id, institution_id, role, full_name, student_code)
values (
  '483462b6-0600-4a99-890b-29715a4ee540',
  '00000000-0000-0000-0000-0000000000a1',
  'student', 'Grace Hopper', 'STU-1001'
) on conflict (id) do nothing;
