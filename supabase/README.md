# CrashGuard AI Supabase backend

Security / RLS overview: **`docs/RLS_AND_SECURITY.md`** (keep in sync when adding migrations).

## Migrations

Apply with Supabase CLI (`supabase db push`) or paste into the SQL editor in order:

1. `20260428120000_emergency_facilities.sql` — OSM-derived facility rows replicated to the app via PowerSync.
2. `20260428120001_incident_retention.sql` — retention columns + purge function for `reported_incidents`.
3. `20260428210000_incident_live_links.sql` — ephemeral tokens for **family tracking URLs** (insert/update RLS for authenticated users; **no public SELECT** — reads only via Edge Function).

## Edge Function: `family-track`

Public browser viewer for contacts: **GET** `/functions/v1/family-track?t=<token>` returns HTML (default) or JSON (`Accept: application/json`). Uses the service role server-side.

1. Deploy with JWT verification disabled for anonymous browser access:
   `supabase functions deploy family-track --no-verify-jwt`
2. Required secrets on the project: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (auto-injected on hosted Supabase).

The Flutter app inserts rows into `incident_live_links` after SOS when the user has a Supabase session.

## Edge Function: `sync-osm-facilities`

Runs **Overpass queries on the server** only (clients must not hit Overpass at scale).

1. Deploy: `supabase functions deploy sync-osm-facilities`
2. Secrets (Dashboard → Edge Functions → Secrets): `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically when deployed via CLI; optionally set:
   - `SYNC_BBOX` — JSON bbox, e.g. `{"south":8,"west":68,"north":37.5,"east":97.5}` (defaults to a rough India box).
   - `OVERPASS_URL` — defaults to `https://overpass-api.de/api/interpreter`.
3. Schedule periodic runs (Dashboard **Edge Functions → sync-osm-facilities → Schedule**, or pg_cron / external cron POST to `/functions/v1/sync-osm-facilities` with auth).

## PowerSync

In the PowerSync dashboard, publish **`public.emergency_facilities`** so offline clients receive facility rows after Postgres upserts. Align RLS with your connector (anon read is allowed in the migration policy for `SELECT`).
