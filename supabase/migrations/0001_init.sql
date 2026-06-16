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
