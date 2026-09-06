-- RoadSOS: auto-delete synced incident rows after 90 days unless extended retention is opted in.
-- Apply in Supabase SQL editor or via CLI. Schedule with pg_cron or Edge Function if pg_cron unavailable.

alter table if exists public.reported_incidents
  add column if not exists created_at timestamptz default now();

alter table if exists public.reported_incidents
  add column if not exists extended_retention boolean default false;

create index if not exists reported_incidents_created_at_idx
  on public.reported_incidents (created_at);

-- PowerSync / client should set extended_retention from app preference when uploading rows.

create or replace function public.purge_expired_reported_incidents()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted bigint;
begin
  delete from public.reported_incidents
  where created_at < (now() - interval '90 days')
    and coalesce(extended_retention, false) = false;
  get diagnostics deleted = row_count;
  return deleted;
end;
$$;

-- Example pg_cron (enable extension in Supabase Dashboard first):
-- select cron.schedule('purge-roadsos-incidents', '0 3 * * *', $$ select public.purge_expired_reported_incidents(); $$);
