-- Ephemeral family tracking links: browser-openable URL with rotating token.
-- Reads for the public URL go through Edge Function (service role), not anon PostgREST.

create table if not exists public.incident_live_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  incident_id text not null,
  token text not null unique,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  triage_summary text,
  severity integer,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists incident_live_links_token_idx on public.incident_live_links (token);
create index if not exists incident_live_links_expires_idx on public.incident_live_links (expires_at);

alter table public.incident_live_links enable row level security;

-- Authenticated users (including anonymous Supabase auth) may create rows for themselves.
create policy incident_live_links_insert_own
  on public.incident_live_links
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy incident_live_links_update_own
  on public.incident_live_links
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- No select/update/delete for public role — family viewers use Edge Function + service role.

comment on table public.incident_live_links is 'RoadSOS family tracking tokens; GET via Edge Function family-track only.';
