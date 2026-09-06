-- Emergency facilities replicated to mobile via PowerSync.
-- Rows are populated by Edge Function `sync-osm-facilities` (Overpass → Postgres), not by clients.

CREATE TABLE IF NOT EXISTS public.emergency_facilities (
  id text PRIMARY KEY,
  name text NOT NULL DEFAULT '',
  type text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  contact_number text,
  capabilities text,
  data_source text DEFAULT 'osm',
  state_code text,
  district text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS emergency_facilities_lat_lon_idx
  ON public.emergency_facilities (latitude, longitude);

ALTER TABLE public.emergency_facilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_read_emergency_facilities" ON public.emergency_facilities;
CREATE POLICY "anon_read_emergency_facilities"
  ON public.emergency_facilities
  FOR SELECT
  TO anon, authenticated
  USING (true);

COMMENT ON TABLE public.emergency_facilities IS
  'OSM/government POIs; clients read via PowerSync; writes via service role (Edge Functions) only.';
