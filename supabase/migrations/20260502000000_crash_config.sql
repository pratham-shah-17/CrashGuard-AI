-- ─────────────────────────────────────────────────────────────────────────────
-- crash_config: remote-configurable crash detection thresholds
--
-- Admins edit rows here; the mobile app fetches on next foreground/restart.
-- No app release is required to tune thresholds.
--
-- Zones:
--   'default'  — applies when no zone-specific row exists or speed is unknown
--   'highway'  — device rolling avg speed > 60 km/h (India national highways)
--   'urban'    — device rolling avg speed ≤ 60 km/h (city / state roads)
--
-- All 11 CRASH_* keys are supported. Missing zone rows fall through to
-- 'default', then to compile-time constants in CrashTuning.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.crash_config (
  zone        TEXT             NOT NULL DEFAULT 'default',
  key         TEXT             NOT NULL,
  value       DOUBLE PRECISION NOT NULL,
  description TEXT,
  updated_at  TIMESTAMPTZ      NOT NULL DEFAULT now(),
  PRIMARY KEY (zone, key)
);

-- Only admins (service role) may write; any authenticated user may read.
ALTER TABLE public.crash_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "crash_config_read"
  ON public.crash_config
  FOR SELECT
  TO authenticated, anon
  USING (true);

-- ── Default zone seed ──────────────────────────────────────────────────────
INSERT INTO public.crash_config (zone, key, value, description) VALUES
  ('default', 'CRASH_IMPACT_THRESHOLD_MS2',      52.0,   'Minimum accelerometer spike to trigger evaluation (m/s²)'),
  ('default', 'CRASH_MIN_APPROACH_SPEED_KMH',    20.0,   'Minimum pre-impact GPS speed for crash to be considered (km/h)'),
  ('default', 'CRASH_STOPPED_SPEED_KMH',          8.0,   'Speed below which vehicle is considered halted post-impact (km/h)'),
  ('default', 'CRASH_SUDDEN_DECEL_DELTA_KMH',    18.0,   'Minimum speed drop (km/h) counted as sharp deceleration'),
  ('default', 'CRASH_SPEED_HISTORY_HORIZON_MS', 4000.0,  'How far back to look for pre-impact speed samples (ms)'),
  ('default', 'CRASH_STILLNESS_STDDEV_MAX_MS2',   2.8,   'Max accelerometer σ for device to be considered still (m/s²)'),
  ('default', 'CRASH_STILLNESS_SAMPLE_WINDOW_MS',1600.0, 'Duration of post-impact stillness measurement window (ms)'),
  ('default', 'CRASH_PRE_IMPACT_LOOKBACK_MS',   2000.0,  'Pre-impact window used to find approach speed (ms)'),
  ('default', 'CRASH_POST_IMPACT_WINDOW_MS',    1200.0,  'Post-impact window used to find minimum speed (ms)'),
  ('default', 'CRASH_INTER_SPIKE_DEBOUNCE_MS',   900.0,  'Minimum gap between handled accelerometer spikes (ms)'),
  ('default', 'CRASH_SOS_COOLDOWN_MS',         45000.0,  'Minimum time between consecutive auto-SOS triggers (ms)')
ON CONFLICT DO NOTHING;

-- ── Highway zone seed ──────────────────────────────────────────────────────
-- At highway speeds (> 60 km/h) crashes produce harder impacts. Lower the
-- impact threshold to catch them earlier, and raise minimum approach speed
-- to suppress slow pothole noise on elevated roads.
INSERT INTO public.crash_config (zone, key, value, description) VALUES
  ('highway', 'CRASH_IMPACT_THRESHOLD_MS2',      48.0,  'Highway: lower threshold — harder impacts expected (m/s²)'),
  ('highway', 'CRASH_MIN_APPROACH_SPEED_KMH',    30.0,  'Highway: higher minimum speed — suppress slow hits (km/h)'),
  ('highway', 'CRASH_STOPPED_SPEED_KMH',          8.0,  'Highway: halt threshold unchanged (km/h)'),
  ('highway', 'CRASH_SUDDEN_DECEL_DELTA_KMH',    22.0,  'Highway: larger speed drop expected in real crashes (km/h)'),
  ('highway', 'CRASH_SPEED_HISTORY_HORIZON_MS', 4000.0, 'Highway: history horizon unchanged (ms)'),
  ('highway', 'CRASH_STILLNESS_STDDEV_MAX_MS2',   2.8,  'Highway: stillness threshold unchanged (m/s²)'),
  ('highway', 'CRASH_STILLNESS_SAMPLE_WINDOW_MS',1600.0,'Highway: stillness window unchanged (ms)'),
  ('highway', 'CRASH_PRE_IMPACT_LOOKBACK_MS',   2000.0, 'Highway: lookback unchanged (ms)'),
  ('highway', 'CRASH_POST_IMPACT_WINDOW_MS',    1200.0, 'Highway: post-impact window unchanged (ms)'),
  ('highway', 'CRASH_INTER_SPIKE_DEBOUNCE_MS',   900.0, 'Highway: debounce unchanged (ms)'),
  ('highway', 'CRASH_SOS_COOLDOWN_MS',         45000.0, 'Highway: SOS cooldown unchanged (ms)')
ON CONFLICT DO NOTHING;

-- ── Urban zone seed ────────────────────────────────────────────────────────
-- Urban roads in India have heavy pothole traffic (25–45 m/s² vertical
-- spikes). Raise the impact threshold slightly to reduce false positives,
-- and lower the minimum approach speed to catch low-speed urban crashes.
INSERT INTO public.crash_config (zone, key, value, description) VALUES
  ('urban', 'CRASH_IMPACT_THRESHOLD_MS2',      57.0,   'Urban: raised threshold to suppress pothole false-positives (m/s²)'),
  ('urban', 'CRASH_MIN_APPROACH_SPEED_KMH',    15.0,   'Urban: lower minimum speed — city crashes happen at lower speeds (km/h)'),
  ('urban', 'CRASH_STOPPED_SPEED_KMH',          6.0,   'Urban: lower halt threshold — traffic jams slow vehicles quickly (km/h)'),
  ('urban', 'CRASH_SUDDEN_DECEL_DELTA_KMH',    14.0,   'Urban: lower drop threshold — slower approach speeds (km/h)'),
  ('urban', 'CRASH_SPEED_HISTORY_HORIZON_MS', 4000.0,  'Urban: history horizon unchanged (ms)'),
  ('urban', 'CRASH_STILLNESS_STDDEV_MAX_MS2',   3.2,   'Urban: slightly relaxed stillness — engine vibration on city roads (m/s²)'),
  ('urban', 'CRASH_STILLNESS_SAMPLE_WINDOW_MS',1600.0, 'Urban: stillness window unchanged (ms)'),
  ('urban', 'CRASH_PRE_IMPACT_LOOKBACK_MS',   2000.0,  'Urban: lookback unchanged (ms)'),
  ('urban', 'CRASH_POST_IMPACT_WINDOW_MS',    1200.0,  'Urban: post-impact window unchanged (ms)'),
  ('urban', 'CRASH_INTER_SPIKE_DEBOUNCE_MS',  1200.0,  'Urban: longer debounce — speed bumps can produce rapid multi-spikes (ms)'),
  ('urban', 'CRASH_SOS_COOLDOWN_MS',         45000.0,  'Urban: SOS cooldown unchanged (ms)')
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.crash_config IS
  'Remote crash detection thresholds. Edit rows here; mobile devices '
  'pick up changes on next app foreground. No release required. '
  'Zones: default | highway (>60 km/h avg) | urban (≤60 km/h avg).';
