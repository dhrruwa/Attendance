-- 0003_profile_and_rfid.sql
-- Additive changes layered on 0001/0002:
--   * student profile fields (phone, college_id) edited in the app Profile tab
--   * room->course mapping + sessions.room for the RFID fallback reader
-- All idempotent so it is safe to re-run.

-- ---- profile fields -------------------------------------------------
alter table public.users add column if not exists phone      text;
alter table public.users add column if not exists college_id text;
-- (users_update_self in 0002 already lets a student update their own row.)

-- ---- RFID fallback: room <-> session resolution ---------------------
alter table public.sessions add column if not exists room text;

create table if not exists public.room_courses (
  room      text primary key,
  course_id uuid not null references public.courses(id) on delete cascade
);
-- Only the service role (edge function) reads this; deny clients by enabling
-- RLS with no policies.
alter table public.room_courses enable row level security;
