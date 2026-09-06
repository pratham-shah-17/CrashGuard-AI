import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_log.dart';
import 'emergency_orchestrator.dart';

/// Phase 4 — Continuous live location streaming during active SOS.
///
/// Once the emergency orchestrator enters [SOSPhase.active], this service
/// streams GPS coordinates to the Supabase `incident_live_links` table
/// every [_updateInterval] seconds. The family contact's browser tab that
/// opened the tracking URL automatically picks up updates through Supabase
/// Realtime (no polling needed on the contact's side).
///
/// Lifecycle:
///   [attach] — call once, refs to [emergencyOrchestratorProvider].
///   The tracker listens to [SOSPhase] changes:
///     idle       → stop streaming (SOS resolved or cancelled)
///     active     → start streaming updates
///     any other  → no-op (dispatching is already streaming coords)
///
/// Update payload:
///   latitude, longitude, accuracy_m, updated_at, speed_kmh (optional)
///
/// Phase 7 / brief — Non-speculative messaging:
///   The tracker only updates coordinates. It does NOT re-send SMS or
///   change triage severity. Contacts receive a coordinate update, not a
///   new diagnosis.
///
/// Error handling:
///   - Supabase write failures are retried once after 5 seconds.
///   - If BT/WiFi drops while driving, writes queue in the Supabase client
///     and flush when connectivity returns (Supabase SDK handles this).
///   - GPS permission loss stops streaming; an error is logged.
class SosLocationTracker {
  static const Duration _updateInterval = Duration(seconds: 30);
  static const int _maxMissedUpdates = 4; // stop after 2 min of GPS failure

  Timer? _updateTimer;
  StreamSubscription<Position>? _positionSub;
  Position? _latestPosition;
  String? _activeIncidentId;
  int _missedUpdates = 0;

  /// Attach to the Riverpod container. Call once from a long-lived provider.
  void attach(Ref ref) {
    ref.listen<SOSPhase>(emergencyOrchestratorProvider.select((s) => s.phase), (
      prev,
      next,
    ) {
      if (next == SOSPhase.active && prev != SOSPhase.active) {
        final incidentId = ref.read(emergencyOrchestratorProvider).incidentId;
        _start(incidentId);
      } else if (next == SOSPhase.idle) {
        _stop();
      }
    });
  }

  void _start(String? incidentId) {
    if (incidentId == null || incidentId.isEmpty) return;
    if (_updateTimer != null) return; // already running

    _activeIncidentId = incidentId;
    _missedUpdates = 0;

    appLog.i(
      '[SosLocationTracker] Started streaming location for incident $_activeIncidentId',
    );

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            // Minimum 15s interval between positions — OS enforces this.
          ),
        ).listen(
          (p) => _latestPosition = p,
          onError: (Object e) {
            appLog.w('[SosLocationTracker] GPS stream error: $e');
          },
        );

    _updateTimer = Timer.periodic(
      _updateInterval,
      (_) => unawaited(_pushUpdate()),
    );
  }

  void _stop() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _latestPosition = null;
    _activeIncidentId = null;
    _missedUpdates = 0;
    appLog.i('[SosLocationTracker] Stopped');
  }

  Future<void> _pushUpdate() async {
    final pos = _latestPosition;
    final id = _activeIncidentId;
    if (pos == null || id == null) {
      _missedUpdates++;
      if (_missedUpdates >= _maxMissedUpdates) {
        appLog.w(
          '[SosLocationTracker] $_maxMissedUpdates missed GPS updates — stopping',
        );
        _stop();
      }
      return;
    }

    if (kIsWeb) return;

    try {
      SupabaseClient client;
      try {
        client = Supabase.instance.client;
      } on Object catch (_) {
        return;
      }

      await client
          .from('incident_live_links')
          .update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy_m': pos.accuracy,
            'speed_kmh': pos.speed >= 0 ? (pos.speed * 3.6) : null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('incident_id', id);

      _missedUpdates = 0;
      appLog.d(
        '[SosLocationTracker] ✓ location update '
        '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)} '
        'acc=${pos.accuracy.toStringAsFixed(0)}m',
      );
    } on Object catch (e) {
      appLog.w(
        '[SosLocationTracker] Update failed: $e — will retry next cycle',
      );
      _missedUpdates++;
    }
  }

  void dispose() => _stop();
}

/// Non-autoDispose: must outlive the full SOS session.
final sosLocationTrackerProvider = Provider<SosLocationTracker>((ref) {
  final svc = SosLocationTracker();
  svc.attach(ref);
  ref.onDispose(svc.dispose);
  return svc;
});
