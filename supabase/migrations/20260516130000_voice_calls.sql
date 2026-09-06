-- ─────────────────────────────────────────────────────────────────────────────
-- Voice calls + WebRTC signaling for RoadSOS
--
-- voice_calls         — one row per call attempt
-- voice_call_signals  — SDP / ICE candidate exchange via Supabase Realtime
--
-- Calls are scoped to Family Circle members only: both caller and callee must
-- already share at least one circle. This stops random users from waking the
-- ringer; the dispatch path is "trusted peers only" by design.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.voice_calls (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references auth.users(id) on delete cascade,
  callee_id uuid not null references auth.users(id) on delete cascade,
  state text not null default 'ringing'
    check (state in ('ringing','answered','ended','missed','declined','error')),
  is_emergency boolean not null default false,
  started_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  ended_by uuid references auth.users(id),
  notes text
);

create index if not exists voice_calls_callee_state_idx
  on public.voice_calls (callee_id, state);

create table if not exists public.voice_call_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.voice_calls(id) on delete cascade,
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('offer','answer','ice','bye')),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists voice_call_signals_call_idx
  on public.voice_call_signals (call_id, created_at);

-- ── RLS ──────────────────────────────────────────────────────────────────────

alter table public.voice_calls         enable row level security;
alter table public.voice_call_signals  enable row level security;

drop policy if exists voice_calls_select on public.voice_calls;
create policy voice_calls_select
  on public.voice_calls
  for select
  to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid());

drop policy if exists voice_calls_insert on public.voice_calls;
create policy voice_calls_insert
  on public.voice_calls
  for insert
  to authenticated
  with check (
    caller_id = auth.uid()
    and public._in_same_circle(callee_id)
  );

drop policy if exists voice_calls_update on public.voice_calls;
create policy voice_calls_update
  on public.voice_calls
  for update
  to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid())
  with check (caller_id = auth.uid() or callee_id = auth.uid());

drop policy if exists voice_call_signals_select on public.voice_call_signals;
create policy voice_call_signals_select
  on public.voice_call_signals
  for select
  to authenticated
  using (to_user = auth.uid() or from_user = auth.uid());

drop policy if exists voice_call_signals_insert on public.voice_call_signals;
create policy voice_call_signals_insert
  on public.voice_call_signals
  for insert
  to authenticated
  with check (
    from_user = auth.uid()
    and public._in_same_circle(to_user)
  );

comment on table public.voice_calls is
  'RoadSOS in-app WebRTC voice calls between Family Circle peers.';
comment on table public.voice_call_signals is
  'SDP / ICE signaling rows for voice_calls; consumed via Supabase Realtime.';
