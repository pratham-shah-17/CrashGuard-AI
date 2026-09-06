-- Core incidents table for RoadSOS (PowerSync upload target).
-- IMPORTANT: keep columns aligned with mobile SQLite `reported_incidents` insert/upsert.

create table if not exists public.reported_incidents (
  id uuid primary key,
  user_id uuid not null default auth.uid(),
  latitude double precision,
  longitude double precision,
  severity integer,
  services_needed text,
  status text,
  reported_at timestamptz,
  created_at timestamptz not null default now(),
  extended_retention boolean default false
);

create index if not exists reported_incidents_user_id_idx
  on public.reported_incidents (user_id);

alter table public.reported_incidents enable row level security;

-- Users can read only their own incidents.
drop policy if exists reported_incidents_select_own on public.reported_incidents;
create policy reported_incidents_select_own
  on public.reported_incidents
  for select
  to authenticated
  using (auth.uid() = user_id);

-- Users can insert incidents for themselves (PowerSync will upsert).
drop policy if exists reported_incidents_insert_own on public.reported_incidents;
create policy reported_incidents_insert_own
  on public.reported_incidents
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Users can update only their own incidents.
drop policy if exists reported_incidents_update_own on public.reported_incidents;
create policy reported_incidents_update_own
  on public.reported_incidents
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

comment on table public.reported_incidents is
  'RoadSOS incident rows uploaded via PowerSync; RLS: owner-only access.';

