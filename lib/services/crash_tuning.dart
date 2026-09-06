import 'remote_crash_config.dart';

/// Crash detection thresholds — now backed by [RemoteCrashConfig].
///
/// All 11 CRASH_* parameters are fetched live from the Supabase
/// `crash_config` table and cached on-device for offline resilience.
/// Changing a value in the table takes effect on the next app foreground
/// (or [RemoteCrashConfig.refresh] call) — no app release required.
///
/// Zone-aware: thresholds automatically switch between 'highway' and
/// 'urban' rows based on the device's rolling GPS speed average.
/// [CrashDetectionService] calls [RemoteCrashConfig.instance.updateSpeedKmh]
/// on every GPS fix.
///
/// Hard-coded compile-time constants act as the ultimate fallback when
/// both Supabase and the local cache are unavailable.
///
/// ## Supabase admin workflow
///
/// To tune thresholds live:
/// ```sql
/// -- Lower highway impact threshold by 10 % (more sensitive):
/// UPDATE crash_config
///   SET value = 47.0, updated_at = now()
///   WHERE zone = 'highway' AND key = 'CRASH_IMPACT_THRESHOLD_MS2';
/// ```
///
/// ## Configurable keys (all zones: 'default', 'highway', 'urban')
/// - CRASH_IMPACT_THRESHOLD_MS2
/// - CRASH_MIN_APPROACH_SPEED_KMH
/// - CRASH_STOPPED_SPEED_KMH
/// - CRASH_SUDDEN_DECEL_DELTA_KMH
/// - CRASH_SPEED_HISTORY_HORIZON_MS
/// - CRASH_STILLNESS_STDDEV_MAX_MS2
/// - CRASH_STILLNESS_SAMPLE_WINDOW_MS
/// - CRASH_PRE_IMPACT_LOOKBACK_MS
/// - CRASH_POST_IMPACT_WINDOW_MS
/// - CRASH_INTER_SPIKE_DEBOUNCE_MS
/// - CRASH_SOS_COOLDOWN_MS
class CrashTuning {
  CrashTuning._();

  static RemoteCrashConfig get _rc => RemoteCrashConfig.instance;

  static double get impactThresholdMs2 =>
      _rc.getDouble('CRASH_IMPACT_THRESHOLD_MS2', 52.0, min: 20.0, max: 160.0);

  static double get minApproachSpeedKmh =>
      _rc.getDouble('CRASH_MIN_APPROACH_SPEED_KMH', 20.0, min: 0.0, max: 160.0);

  static double get stoppedSpeedKmh =>
      _rc.getDouble('CRASH_STOPPED_SPEED_KMH', 8.0, min: 0.0, max: 40.0);

  static double get suddenDecelDeltaKmh =>
      _rc.getDouble('CRASH_SUDDEN_DECEL_DELTA_KMH', 18.0, min: 2.0, max: 120.0);

  static int get speedHistoryHorizonMs =>
      _rc.getInt('CRASH_SPEED_HISTORY_HORIZON_MS', 4000, min: 1000, max: 20000);

  static double get stillnessStdDevMaxMs2 =>
      _rc.getDouble('CRASH_STILLNESS_STDDEV_MAX_MS2', 2.8, min: 0.6, max: 12.0);

  static int get stillnessSampleWindowMs =>
      _rc.getInt('CRASH_STILLNESS_SAMPLE_WINDOW_MS', 1600, min: 400, max: 8000);

  static int get preImpactLookbackMs =>
      _rc.getInt('CRASH_PRE_IMPACT_LOOKBACK_MS', 2000, min: 500, max: 10000);

  static int get postImpactWindowMs =>
      _rc.getInt('CRASH_POST_IMPACT_WINDOW_MS', 1200, min: 300, max: 8000);

  static int get interSpikeDebounceMs =>
      _rc.getInt('CRASH_INTER_SPIKE_DEBOUNCE_MS', 900, min: 100, max: 10000);

  static int get sosCooldownMs => _rc.getInt(
    'CRASH_SOS_COOLDOWN_MS',
    45000,
    min: 5000,
    max: 10 * 60 * 1000,
  );
}
