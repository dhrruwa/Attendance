-- 0005_offerings.sql
-- Multi-subject / multi-section model + weekly timetable.
--   subject  : reusable catalog unit (DBMS, OS, ...)
--   section  : a student cohort (e.g. "6th sem CSE-A", "4th sem CSE-A")
--   offering : a teacher teaches a subject to a section in a room (the unit
--              attendance is taken against; replaces the old "course")
--   section_students : 60-ish students per section
--   timetable: when an offering meets (weekday + time + room)
-- sessions gain offering_id; course_id becomes optional (legacy).

create table if not exists public.subjects (
  id   uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null
);

create table if not exists public.sections (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name           text not null,          -- "CSE-A"
  semester       int,                    -- 6, 4, ...
  dept           text
);

create table if not exists public.offerings (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  subject_id     uuid not null references public.subjects(id)  on delete cascade,
  section_id     uuid not null references public.sections(id)  on delete cascade,
  teacher_id     uuid not null references public.users(id)     on delete restrict,
  room           text,
  unique (subject_id, section_id, teacher_id)
);
create index if not exists offerings_teacher_idx on public.offerings(teacher_id);
create index if not exists offerings_section_idx on public.offerings(section_id);

create table if not exists public.section_students (
  section_id uuid not null references public.sections(id) on delete cascade,
  student_id uuid not null references public.users(id)    on delete cascade,
  primary key (section_id, student_id)
);
create index if not exists section_students_student_idx on public.section_students(student_id);

create table if not exists public.timetable (
  id          uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings(id) on delete cascade,
  weekday     int  not null,   -- 1=Mon .. 7=Sun (ISO)
  start_time  time not null,
  end_time    time not null,
  room        text
);
create index if not exists timetable_offering_idx on public.timetable(offering_id);
create index if not exists timetable_weekday_idx on public.timetable(weekday);

-- sessions: attach to an offering; course_id now optional (legacy sessions).
alter table public.sessions add column if not exists offering_id uuid references public.offerings(id) on delete cascade;
alter table public.sessions alter column course_id drop not null;
create index if not exists sessions_offering_idx on public.sessions(offering_id);

-- ---- helper predicates (SECURITY DEFINER, used by RLS) --------------
create or replace function public.owns_offering(p_offering uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from offerings o where o.id = p_offering and o.teacher_id = auth.uid());
$$;

create or replace function public.my_section_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select section_id from section_students where student_id = auth.uid();
$$;

create or replace function public.teaches_section(p_section uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from offerings o where o.section_id = p_section and o.teacher_id = auth.uid());
$$;

-- ---- RLS ------------------------------------------------------------
alter table public.subjects         enable row level security;
alter table public.sections         enable row level security;
alter table public.offerings        enable row level security;
alter table public.section_students enable row level security;
alter table public.timetable        enable row level security;

-- catalog: any authenticated user may read subjects + sections.
drop policy if exists subjects_read on public.subjects;
create policy subjects_read on public.subjects for select to authenticated using (true);
drop policy if exists sections_read on public.sections;
create policy sections_read on public.sections for select to authenticated using (true);

-- offerings: the teacher of it, or a student in its section.
drop policy if exists offerings_read on public.offerings;
create policy offerings_read on public.offerings for select to authenticated
  using (teacher_id = auth.uid() or section_id in (select public.my_section_ids()));

-- section_students: the student themself, or a teacher who teaches the section.
drop policy if exists section_students_read on public.section_students;
create policy section_students_read on public.section_students for select to authenticated
  using (student_id = auth.uid() or public.teaches_section(section_id));

-- timetable: teacher of the offering, or a student in its section.
drop policy if exists timetable_read on public.timetable;
create policy timetable_read on public.timetable for select to authenticated
  using (public.owns_offering(offering_id)
         or offering_id in (select id from public.offerings where section_id in (select public.my_section_ids())));

-- sessions: allow offering-based reads (teacher owner or student in section).
drop policy if exists sessions_offering_read on public.sessions;
create policy sessions_offering_read on public.sessions for select to authenticated
  using (
    teacher_id = auth.uid()
    or (offering_id is not null and offering_id in
         (select id from public.offerings where section_id in (select public.my_section_ids())))
  );
