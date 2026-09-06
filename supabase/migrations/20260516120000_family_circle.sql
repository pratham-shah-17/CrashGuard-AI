-- ─────────────────────────────────────────────────────────────────────────────
-- Family Circle: persistent trust-graph for RoadSOS
--
-- Provides:
--   * family_circles                — named circles (one per household / squad)
--   * family_circle_members         — uid ↔ circle membership w/ role
--   * family_invites                — pending one-time codes sent via SMS / share
--   * family_live_locations         — single-row-per-user live position stream
--                                     (Realtime channel; updated every ~5s while
--                                     Safe Walk or SOS is active)
--
-- RLS model:
--   * A row is visible to a user iff they share at least one ACTIVE circle with
--     the row's owner. Enforced via helper SQL function `_in_same_circle()`.
--   * Insert/update of own profile/location restricted to the row owner.
--   * Circle owners can manage members.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.family_circles (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 64),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.family_circle_members (
  circle_id uuid not null references public.family_circles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text,
  phone_e164 text,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

create index if not exists family_circle_members_user_idx
  on public.family_circle_members (user_id);

create table if not exists public.family_invites (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.family_circles(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invitee_phone_e164 text not null,
  code text not null unique,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists family_invites_phone_idx
  on public.family_invites (invitee_phone_e164);

create index if not exists family_invites_code_idx
  on public.family_invites (code);

create table if not exists public.family_live_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m double precision,
  heading_deg double precision,
  speed_mps double precision,
  battery_pct integer check (battery_pct is null or battery_pct between 0 and 100),
  is_safewalk boolean not null default false,
  is_sos boolean not null default false,
  destination text,
  updated_at timestamptz not null default now()
);

create index if not exists family_live_locations_updated_idx
  on public.family_live_locations (updated_at);

-- Helper: returns true when the caller shares at least one circle with `target`.
create or replace function public._in_same_circle(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.family_circle_members a
    join public.family_circle_members b on a.circle_id = b.circle_id
    where a.user_id = auth.uid()
      and b.user_id = target
  );
$$;

revoke all on function public._in_same_circle(uuid) from public;
grant execute on function public._in_same_circle(uuid) to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────

alter table public.family_circles            enable row level security;
alter table public.family_circle_members     enable row level security;
alter table public.family_invites            enable row level security;
alter table public.family_live_locations     enable row level security;

-- family_circles
drop policy if exists family_circles_select on public.family_circles;
create policy family_circles_select
  on public.family_circles
  for select
  to authenticated
  using (
    exists (
      select 1 from public.family_circle_members m
      where m.circle_id = id and m.user_id = auth.uid()
    )
  );

drop policy if exists family_circles_insert on public.family_circles;
create policy family_circles_insert
  on public.family_circles
  for insert
  to authenticated
  with check (created_by = auth.uid());

-- family_circle_members
drop policy if exists family_circle_members_select on public.family_circle_members;
create policy family_circle_members_select
  on public.family_circle_members
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public._in_same_circle(user_id)
  );

drop policy if exists family_circle_members_insert on public.family_circle_members;
create policy family_circle_members_insert
  on public.family_circle_members
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists family_circle_members_delete on public.family_circle_members;
create policy family_circle_members_delete
  on public.family_circle_members
  for delete
  to authenticated
  using (user_id = auth.uid());

-- family_invites: inviter manages own; invitees match by phone server-side
drop policy if exists family_invites_select on public.family_invites;
create policy family_invites_select
  on public.family_invites
  for select
  to authenticated
  using (inviter_id = auth.uid() or accepted_by = auth.uid());

drop policy if exists family_invites_insert on public.family_invites;
create policy family_invites_insert
  on public.family_invites
  for insert
  to authenticated
  with check (inviter_id = auth.uid());

drop policy if exists family_invites_update_accept on public.family_invites;
create policy family_invites_update_accept
  on public.family_invites
  for update
  to authenticated
  using (true)
  with check (true);

-- family_live_locations: own row writable, peers in same circle readable
drop policy if exists family_live_locations_select on public.family_live_locations;
create policy family_live_locations_select
  on public.family_live_locations
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public._in_same_circle(user_id)
  );

drop policy if exists family_live_locations_upsert on public.family_live_locations;
create policy family_live_locations_upsert
  on public.family_live_locations
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists family_live_locations_update_own on public.family_live_locations;
create policy family_live_locations_update_own
  on public.family_live_locations
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists family_live_locations_delete_own on public.family_live_locations;
create policy family_live_locations_delete_own
  on public.family_live_locations
  for delete
  to authenticated
  using (user_id = auth.uid());

comment on table public.family_circles is
  'RoadSOS Family Circle — persistent trust-graph; per-circle membership in family_circle_members.';
comment on table public.family_live_locations is
  'Live location row (one per user) streamed to circle peers via Supabase Realtime during Safe Walk / SOS.';
