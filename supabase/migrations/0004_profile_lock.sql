-- 0004_profile_lock.sql
-- Profile becomes immutable after the student's first save. Changing locked
-- fields afterwards requires a teacher to approve a change request, which opens
-- a one-shot edit window. Enforced by a trigger (not just the UI), so a modified
-- client cannot bypass it.

-- ---- lock state -----------------------------------------------------
alter table public.users add column if not exists profile_locked boolean not null default false;
alter table public.users add column if not exists edit_allowed   boolean not null default false;

-- ---- change-request inbox -------------------------------------------
create table if not exists public.profile_change_requests (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.users(id) on delete cascade,
  reason      text,
  status      text not null default 'pending',  -- pending | approved | rejected
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.users(id)
);
create index if not exists pcr_student_idx on public.profile_change_requests(student_id);
alter table public.profile_change_requests enable row level security;

-- student: create + read OWN requests; teacher: read requests of students they teach.
drop policy if exists pcr_student_insert on public.profile_change_requests;
create policy pcr_student_insert on public.profile_change_requests
  for insert to authenticated
  with check (student_id = auth.uid());

drop policy if exists pcr_read on public.profile_change_requests;
create policy pcr_read on public.profile_change_requests
  for select to authenticated
  using (student_id = auth.uid() or public.teaches_student(student_id));
-- (resolution is done by the edge function with the service role.)

-- ---- enforcement trigger -------------------------------------------
create or replace function public.enforce_profile_lock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  locked_changed boolean;
begin
  locked_changed :=
       (new.full_name    is distinct from old.full_name)
    or (new.phone        is distinct from old.phone)
    or (new.college_id   is distinct from old.college_id)
    or (new.student_code is distinct from old.student_code);

  -- Only a teacher of this student (or the service role) may OPEN an edit window.
  if new.edit_allowed = true and old.edit_allowed = false then
    if not (public.teaches_student(new.id)
            or coalesce(auth.role(), '') = 'service_role') then
      raise exception 'Only a teacher can allow profile edits';
    end if;
  end if;

  -- Locked + no open window => reject changes to locked fields.
  if old.profile_locked and not old.edit_allowed and locked_changed then
    raise exception 'Profile is locked. Request a change and have a teacher approve it.';
  end if;

  -- A locked-field edit during an open window consumes the window (re-locks).
  if old.edit_allowed and locked_changed then
    new.edit_allowed := false;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_profile_lock on public.users;
create trigger trg_enforce_profile_lock
  before update on public.users
  for each row execute function public.enforce_profile_lock();
