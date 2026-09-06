-- ─────────────────────────────────────────────────────────────────────────────
-- crash_config_regions: GPS geofence regions for per-region crash thresholds
--
-- Each row defines a bounding box (min/max lat/lng) that maps to a zone
-- name (which must match a zone in crash_config). When a device's GPS fix
-- falls inside a region, that zone's thresholds are activated immediately.
--
-- Priority: higher priority rows are matched first. If a fix is inside
-- multiple overlapping bounding boxes, the highest-priority match wins.
--
-- If no region matches, the mobile app falls back to a rolling-speed
-- heuristic (highway if avg > 60 km/h, urban otherwise).
--
-- Admin workflow: add, edit, or deactivate rows in this table.
-- Changes propagate to devices on the next app foreground event or within
-- 15 minutes via periodic refresh. No app release required.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.crash_config_regions (
  id          UUID             NOT NULL DEFAULT gen_random_uuid(),
  name        TEXT             NOT NULL,
  zone        TEXT             NOT NULL,           -- must match a zone in crash_config
  min_lat     DOUBLE PRECISION NOT NULL,
  max_lat     DOUBLE PRECISION NOT NULL,
  min_lng     DOUBLE PRECISION NOT NULL,
  max_lng     DOUBLE PRECISION NOT NULL,
  priority    INT              NOT NULL DEFAULT 0, -- higher value = checked first
  description TEXT,
  active      BOOLEAN          NOT NULL DEFAULT true,
  updated_at  TIMESTAMPTZ      NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  CONSTRAINT crash_config_regions_lat_check CHECK (min_lat < max_lat),
  CONSTRAINT crash_config_regions_lng_check CHECK (min_lng < max_lng),
  CONSTRAINT crash_config_regions_zone_check CHECK (zone IN ('default', 'highway', 'urban'))
);

-- Only authenticated/anon users read active regions; admins write via service role.
ALTER TABLE public.crash_config_regions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "crash_config_regions_read"
  ON public.crash_config_regions
  FOR SELECT
  TO authenticated, anon
  USING (active = true);

-- ── Seed: major Indian urban metros ───────────────────────────────────────
-- Higher priority (10) so city zones override any overlapping highway rows.
INSERT INTO public.crash_config_regions
  (name, zone, min_lat, max_lat, min_lng, max_lng, priority, description)
VALUES
  ('Delhi NCR Urban',
   'urban', 28.40, 28.88, 76.84, 77.35, 10,
   'National Capital Region — includes Delhi, Gurgaon, Noida core areas'),

  ('Mumbai Metropolitan Urban',
   'urban', 18.89, 19.27, 72.77, 73.03, 10,
   'Mumbai island + suburbs (Thane, Navi Mumbai fringe excluded)'),

  ('Bengaluru Urban',
   'urban', 12.84, 13.14, 77.45, 77.78, 10,
   'Bengaluru city zone — high two-wheeler and auto density'),

  ('Chennai Urban',
   'urban', 12.95, 13.22, 80.10, 80.30, 10,
   'Chennai metropolitan core'),

  ('Kolkata Urban',
   'urban', 22.45, 22.65, 88.30, 88.50, 10,
   'Kolkata and Howrah bridge zone'),

  ('Hyderabad Urban',
   'urban', 17.30, 17.55, 78.35, 78.60, 10,
   'GHMC boundary zone — high urban crash density'),

  ('Pune Urban',
   'urban', 18.45, 18.60, 73.78, 73.96, 10,
   'Pune municipal limits — elevated pothole risk'),

  ('Ahmedabad Urban',
   'urban', 22.95, 23.15, 72.50, 72.70, 10,
   'AMC boundary — heavy two-wheeler traffic')

ON CONFLICT DO NOTHING;

-- ── Seed: major national highway corridors ─────────────────────────────────
-- Lower priority (5) so they yield to overlapping urban metro rows above.
-- These cover highway sections outside city limits.
INSERT INTO public.crash_config_regions
  (name, zone, min_lat, max_lat, min_lng, max_lng, priority, description)
VALUES
  ('NH 44 North Corridor (Delhi–Ambala)',
   'highway', 28.88, 30.40, 76.80, 77.10, 5,
   'NH44 north of Delhi NCR toward Ambala — 4-lane divided carriageway'),

  ('NH 44 South Corridor (Bengaluru–Chennai)',
   'highway', 12.85, 13.14, 77.65, 80.10, 5,
   'NH44 between Bengaluru and Chennai outskirts — high-speed divided highway'),

  ('NH 48 Mumbai–Pune Expressway',
   'highway', 18.60, 19.27, 73.03, 73.30, 5,
   'Mumbai–Pune Expressway and old NH4 bypass — 100 km/h design speed'),

  ('NH 19 Agra–Kanpur',
   'highway', 26.45, 27.20, 79.90, 80.40, 5,
   'NH19 (old NH2) Agra–Kanpur stretch — heavy goods vehicle corridor'),

  ('NH 66 Coastal Corridor (Goa section)',
   'highway', 14.90, 15.80, 73.80, 74.20, 5,
   'NH66 Goa coastal highway — tourist high-speed zone, narrow carriageway'),

  ('Yamuna Expressway',
   'highway', 27.17, 28.40, 77.40, 77.70, 7,
   'Yamuna Expressway (Agra–Greater Noida) — 100 km/h limit, elevated crash rate'),

  ('Delhi–Mumbai Expressway (partial open)',
   'highway', 25.20, 28.40, 76.00, 77.20, 7,
   'Delhi–Mumbai Expressway operational sections — 8-lane, 120 km/h design speed')

ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.crash_config_regions IS
  'GPS geofence regions for zone-based crash threshold selection. '
  'Add or edit rows to define urban/highway zones; devices pick up changes '
  'on next foreground refresh. Zone must match a zone in crash_config table.';
