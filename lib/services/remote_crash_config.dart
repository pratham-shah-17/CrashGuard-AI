import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_log.dart';
import '../database/app_database.dart';

/// GPS-based road zone classification.
///
/// Priority order for zone selection:
///   1. GPS-region lookup — bounding boxes fetched from `crash_config_regions`
///      Supabase table. Enables admin-defined regions (urban metros, highway
///      corridors, known black-spot zones) that override speed heuristics.
///   2. Rolling-speed heuristic — fallback when no region matches: highway if
///      30-second average speed > [_highwaySpeedKmh], otherwise urban.
///   3. Unknown — no GPS data yet; the 'default' config row applies.
enum RoadZone {
  /// No GPS data yet — uses the 'default' config row.
  unknown,

  /// Urban zone: city / state roads.
  /// Potholes are frequent → slightly raised impact threshold.
  urban,

  /// Highway zone: national highway / expressway.
  /// Faster impacts, less pothole noise → lower impact threshold.
  highway,
}

/// A geofenced region with an assigned road zone.
///
/// Rows come from the `crash_config_regions` Supabase table.
/// Bounding boxes are sufficient precision for zone assignment;
/// complex polygon queries are unnecessary at this granularity.
class _ConfigRegion {
  final String name;
  final String zone;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final int priority;

  const _ConfigRegion({
    required this.name,
    required this.zone,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.priority,
  });

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
}

/// Manages crash detection thresholds fetched from Supabase remote config.
///
/// ## Fetch lifecycle
///
/// Phase 1 (app start, before Supabase auth):
///   Call [loadCachedValues] from [RuntimeConfig.bootstrap].
///   Loads the last good values from SharedPreferences immediately so
///   CrashTuning is ready before the first GPS event.
///
/// Phase 2 (after [bootstrapSupabaseAuth]):
///   Call [refresh] to fetch live values from Supabase.
///   Then call [startPeriodicRefresh] to re-fetch every [refreshInterval].
///
/// Phase 3 (app foreground):
///   Call [onAppForeground] from the lifecycle observer in main.dart.
///   Triggers an immediate refresh so threshold changes propagate
///   without waiting for the next periodic tick.
///
/// ## Zone selection
///
/// Each GPS fix calls [updateLocation]. Zone resolution:
///   1. Iterate `crash_config_regions` rows (sorted by priority descending).
///      First bounding-box match wins.
///   2. If no region matches, classify from rolling 30-second speed average.
///   3. If no speed data, zone = [RoadZone.unknown] → 'default' config row.
///
/// ## Admin workflow
///
/// Edit rows in the Supabase dashboard; devices pick up changes on the next
/// foreground event or periodic refresh. No app release required.
///
/// ```sql
/// -- Tighten highway sensitivity across India immediately:
/// UPDATE crash_config
///   SET value = 45.0, updated_at = now()
///   WHERE zone = 'highway' AND key = 'CRASH_IMPACT_THRESHOLD_MS2';
///
/// -- Add a new black-spot urban zone (Pune ring road):
/// INSERT INTO crash_config_regions (name, zone, min_lat, max_lat, min_lng, max_lng, priority)
///   VALUES ('Pune Ring Road', 'urban', 18.40, 18.70, 73.75, 74.00, 20);
/// ```
class RemoteCrashConfig {
  RemoteCrashConfig._();

  static final RemoteCrashConfig instance = RemoteCrashConfig._();

  // ── Configuration ──────────────────────────────────────────────────────────

  static const String _cacheKey = 'remote_crash_config_v2';
  static const String _regionsCacheKey = 'remote_crash_config_regions_v1';

  /// Re-fetch interval while the app is active.
  static const Duration refreshInterval = Duration(minutes: 15);

  /// Speed (km/h) above which rolling average triggers highway zone.
  static const double _highwaySpeedKmh = 60.0;

  /// Rolling window for speed-based zone heuristic.
  static const int _zoneSpeedWindowSec = 30;

  // ── Hard-coded compile-time defaults ──────────────────────────────────────
  // These are the ultimate fallback — active when Supabase is unreachable and
  // no local cache exists (e.g., first install with no connectivity).
  static const Map<String, double> _hardcodedDefaults = {
    'CRASH_IMPACT_THRESHOLD_MS2': 52.0,
    'CRASH_MIN_APPROACH_SPEED_KMH': 20.0,
    'CRASH_STOPPED_SPEED_KMH': 8.0,
    'CRASH_SUDDEN_DECEL_DELTA_KMH': 18.0,
    'CRASH_SPEED_HISTORY_HORIZON_MS': 4000.0,
    'CRASH_STILLNESS_STDDEV_MAX_MS2': 2.8,
    'CRASH_STILLNESS_SAMPLE_WINDOW_MS': 1600.0,
    'CRASH_PRE_IMPACT_LOOKBACK_MS': 2000.0,
    'CRASH_POST_IMPACT_WINDOW_MS': 1200.0,
    'CRASH_INTER_SPIKE_DEBOUNCE_MS': 900.0,
    'CRASH_SOS_COOLDOWN_MS': 45000.0,
  };

  // ── Runtime state ──────────────────────────────────────────────────────────

  /// Threshold values per zone name ('default', 'highway', 'urban', …).
  final Map<String, Map<String, double>> _values = {};

  /// GPS geofence regions from `crash_config_regions`, sorted by priority desc.
  final List<_ConfigRegion> _regions = [];

  RoadZone _currentZone = RoadZone.unknown;
  String? _currentRegionName;

  /// Rolling window of (timestamp, speedKmh) for speed-based zone fallback.
  final List<(DateTime, double)> _speedWindow = [];

  Timer? _refreshTimer;

  // ── Public state accessors ─────────────────────────────────────────────────

  RoadZone get currentZone => _currentZone;

  /// Name of the active geofence region, or null if speed heuristic is in use.
  String? get currentRegionName => _currentRegionName;

  // ── Phase 1: Cache bootstrap ───────────────────────────────────────────────

  /// Load the last cached values from SharedPreferences.
  ///
  /// Call this from [RuntimeConfig.bootstrap] (Phase 1, before Supabase auth).
  /// Completes synchronously-equivalent (single async I/O); does NOT touch
  /// the network. Falls through to hardcoded defaults if no cache exists.
  Future<void> loadCachedValues() async {
    await Future.wait([_loadThresholdsFromCache(), _loadRegionsFromCache()]);
    appLog.d(
      '[RemoteCrashConfig] Cache loaded. '
      'zones=${_values.keys.toList()} regions=${_regions.length}',
    );
  }

  // ── Phase 2: Remote fetch ──────────────────────────────────────────────────

  /// Fetch live threshold and region data from Supabase.
  ///
  /// Call this from main() after [bootstrapSupabaseAuth] completes.
  /// Safe to call multiple times (e.g., from the periodic timer and from
  /// [onAppForeground]). Each call is rate-limited by the 5-second timeout
  /// inside the fetch helpers.
  Future<void> refresh() async {
    if (!isSupabaseSdkInitialized) {
      appLog.d('[RemoteCrashConfig] Skipping refresh — Supabase not ready');
      return;
    }
    await Future.wait([
      _fetchThresholdsFromSupabase(),
      _fetchRegionsFromSupabase(),
    ]);
  }

  /// Start periodic background refresh every [refreshInterval].
  ///
  /// Call once from main() after the first successful [refresh].
  /// Safe to call multiple times — cancels any existing timer first.
  void startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      appLog.d('[RemoteCrashConfig] Periodic refresh triggered');
      refresh();
    });
    appLog.i(
      '[RemoteCrashConfig] Periodic refresh armed: every '
      '${refreshInterval.inMinutes} min',
    );
  }

  /// Call when the app returns to foreground so threshold changes propagate
  /// immediately rather than waiting for the next periodic timer tick.
  Future<void> onAppForeground() async {
    appLog.d('[RemoteCrashConfig] App foregrounded — refreshing thresholds');
    await refresh();
  }

  // ── Zone update ────────────────────────────────────────────────────────────

  /// Update zone from a GPS fix.
  ///
  /// Resolution order:
  ///   1. Match [lat]/[lng] against loaded geofence regions (priority-ordered).
  ///   2. If no region matches, classify from rolling [speedKmh] average.
  ///   3. If speed data is absent, zone stays [RoadZone.unknown].
  ///
  /// Call from [CrashDetectionService._onPosition] on every GPS event.
  void updateLocation(double lat, double lng, double speedKmh) {
    _updateSpeedWindow(speedKmh);

    // 1. GPS-region lookup (highest priority).
    for (final region in _regions) {
      if (region.contains(lat, lng)) {
        final newZone = _parseZone(region.zone);
        if (newZone != _currentZone || _currentRegionName != region.name) {
          appLog.d(
            '[RemoteCrashConfig] Zone ← region "${region.name}" '
            '(${region.zone}): $_currentZone → $newZone',
          );
          _currentZone = newZone;
          _currentRegionName = region.name;
        }
        return;
      }
    }

    // 2. Speed-based fallback.
    _currentRegionName = null;
    _classifyFromSpeed();
  }

  // ── Threshold getters ──────────────────────────────────────────────────────

  /// Retrieve a double threshold for the current zone, with bounds enforcement.
  ///
  /// Lookup order: zone row → 'default' row → hardcoded constant → [fallback].
  double getDouble(String key, double fallback, {double? min, double? max}) {
    double? v;
    if (_currentZone != RoadZone.unknown) {
      v = _values[_currentZone.name]?[key];
    }
    v ??= _values['default']?[key];
    v ??= _hardcodedDefaults[key] ?? fallback;
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    return v;
  }

  /// Retrieve an int threshold for the current zone, with bounds enforcement.
  int getInt(String key, int fallback, {int? min, int? max}) {
    double? raw;
    if (_currentZone != RoadZone.unknown) {
      raw = _values[_currentZone.name]?[key];
    }
    raw ??= _values['default']?[key];
    raw ??= _hardcodedDefaults[key] ?? fallback.toDouble();
    var v = raw.round();
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    return v;
  }

  // ── Private: Supabase fetch ────────────────────────────────────────────────

  Future<void> _fetchThresholdsFromSupabase() async {
    try {
      final rows = await Supabase.instance.client
          .from('crash_config')
          .select('zone, key, value')
          .timeout(const Duration(seconds: 5));

      if (rows.isEmpty) {
        appLog.d(
          '[RemoteCrashConfig] crash_config table empty — defaults retained',
        );
        return;
      }

      final fetched = <String, Map<String, double>>{};
      for (final row in rows) {
        final zone = (row['zone'] as String?) ?? 'default';
        final key = (row['key'] as String?) ?? '';
        final value = (row['value'] as num?)?.toDouble();
        if (key.isEmpty || value == null) continue;
        fetched.putIfAbsent(zone, () => {})[key] = value;
      }

      _values
        ..clear()
        ..addAll(fetched);

      await _persistThresholdsToCache();
      appLog.i(
        '[RemoteCrashConfig] Thresholds refreshed: '
        '${rows.length} rows, zones=${_values.keys.toList()}',
      );
    } on Object catch (e, st) {
      appLog.w(
        '[RemoteCrashConfig] Threshold fetch failed — cached values in use',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _fetchRegionsFromSupabase() async {
    try {
      final rows = await Supabase.instance.client
          .from('crash_config_regions')
          .select('name, zone, min_lat, max_lat, min_lng, max_lng, priority')
          .eq('active', true)
          .order('priority', ascending: false)
          .timeout(const Duration(seconds: 5));

      final fetched = <_ConfigRegion>[];
      for (final row in rows) {
        try {
          fetched.add(
            _ConfigRegion(
              name: row['name'] as String,
              zone: row['zone'] as String,
              minLat: (row['min_lat'] as num).toDouble(),
              maxLat: (row['max_lat'] as num).toDouble(),
              minLng: (row['min_lng'] as num).toDouble(),
              maxLng: (row['max_lng'] as num).toDouble(),
              priority: (row['priority'] as num).toInt(),
            ),
          );
        } on Object catch (_) {}
      }

      _regions
        ..clear()
        ..addAll(fetched);

      await _persistRegionsToCache();
      appLog.i(
        '[RemoteCrashConfig] Regions refreshed: ${_regions.length} geofences',
      );
    } on Object catch (e, st) {
      appLog.w(
        '[RemoteCrashConfig] Region fetch failed — cached regions in use',
        error: e,
        stackTrace: st,
      );
    }
  }

  // ── Private: SharedPreferences cache ──────────────────────────────────────

  Future<void> _loadThresholdsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _values.clear();
      for (final entry in decoded.entries) {
        final inner = entry.value as Map<String, dynamic>;
        _values[entry.key] = inner.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        );
      }
    } on Object catch (e) {
      appLog.d('[RemoteCrashConfig] Threshold cache empty (first run): $e');
    }
  }

  Future<void> _persistThresholdsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_values));
    } on Object catch (e) {
      appLog.d('[RemoteCrashConfig] Threshold cache write failed: $e');
    }
  }

  Future<void> _loadRegionsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_regionsCacheKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _regions.clear();
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        _regions.add(
          _ConfigRegion(
            name: m['name'] as String,
            zone: m['zone'] as String,
            minLat: (m['min_lat'] as num).toDouble(),
            maxLat: (m['max_lat'] as num).toDouble(),
            minLng: (m['min_lng'] as num).toDouble(),
            maxLng: (m['max_lng'] as num).toDouble(),
            priority: (m['priority'] as num).toInt(),
          ),
        );
      }
    } on Object catch (e) {
      appLog.d('[RemoteCrashConfig] Region cache empty (first run): $e');
    }
  }

  Future<void> _persistRegionsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _regions
          .map(
            (r) => {
              'name': r.name,
              'zone': r.zone,
              'min_lat': r.minLat,
              'max_lat': r.maxLat,
              'min_lng': r.minLng,
              'max_lng': r.maxLng,
              'priority': r.priority,
            },
          )
          .toList();
      await prefs.setString(_regionsCacheKey, jsonEncode(list));
    } on Object catch (e) {
      appLog.d('[RemoteCrashConfig] Region cache write failed: $e');
    }
  }

  // ── Private: speed window + zone heuristic ─────────────────────────────────

  void _updateSpeedWindow(double speedKmh) {
    final now = DateTime.now();
    _speedWindow.add((now, speedKmh));
    final cutoff = now.subtract(Duration(seconds: _zoneSpeedWindowSec));
    _speedWindow.removeWhere((e) => e.$1.isBefore(cutoff));
  }

  void _classifyFromSpeed() {
    if (_speedWindow.isEmpty) {
      _setZone(RoadZone.unknown, source: 'no-speed-data');
      return;
    }
    final avg =
        _speedWindow.map((e) => e.$2).reduce((a, b) => a + b) /
        _speedWindow.length;
    final zone = avg >= _highwaySpeedKmh ? RoadZone.highway : RoadZone.urban;
    _setZone(
      zone,
      source: 'speed-heuristic(avg=${avg.toStringAsFixed(1)} km/h)',
    );
  }

  void _setZone(RoadZone zone, {required String source}) {
    if (zone != _currentZone) {
      appLog.d('[RemoteCrashConfig] Zone: $_currentZone → $zone [$source]');
      _currentZone = zone;
    }
  }

  static RoadZone _parseZone(String zone) {
    switch (zone) {
      case 'highway':
        return RoadZone.highway;
      case 'urban':
        return RoadZone.urban;
      default:
        return RoadZone.unknown;
    }
  }
}
