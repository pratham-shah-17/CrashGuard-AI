import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../logging/app_log.dart';

/// The driving context inferred from GPS speed.
enum DrivingMode {
  /// User is stationary or walking — standard crash monitoring sensitivity.
  stationary,

  /// User is in a vehicle at highway speed for at least [_activationWindowMs].
  /// Effects:
  ///   - CrashDetectionService: gyro multiplier threshold applied more aggressively.
  ///   - EmergencyOrchestrator: logs driving context in incident record.
  ///   - Dashboard: shows persistent "Driving mode — crash detection armed" banner.
  driving,
}

/// Detects when the user is in a moving vehicle using GPS speed.
///
/// Activates after [_activationWindowMs] milliseconds above [_driveThresholdKmh].
/// Deactivates after [_deactivationWindowMs] milliseconds below [_stopThresholdKmh].
///
/// Uses [LocationAccuracy.medium] with a 20-metre distance filter to avoid
/// waking GPS hardware on every tick — suitable for always-on background use.
///
/// Degrades gracefully: if GPS is unavailable or permission denied, stays in
/// [DrivingMode.stationary] (no impact on other services).
class DrivingModeService extends StateNotifier<DrivingMode> {
  DrivingModeService() : super(DrivingMode.stationary) {
    _startTracking();
  }

  static const double _driveThresholdKmh = 40.0;
  static const double _stopThresholdKmh = 12.0;
  static const int _activationWindowMs = 25000;
  static const int _deactivationWindowMs = 30000;

  StreamSubscription<Position>? _posSub;
  DateTime? _aboveThresholdSince;
  DateTime? _belowThresholdSince;

  void _startTracking() {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 20,
        ),
      ).listen(_onPosition, onError: (Object _) {});
    } on Object catch (_) {}
  }

  void _onPosition(Position p) {
    if (p.speed < 0) return;
    final kmh = p.speed * 3.6;
    final now = DateTime.now();

    if (kmh >= _driveThresholdKmh) {
      _belowThresholdSince = null;
      _aboveThresholdSince ??= now;
      if (state == DrivingMode.stationary &&
          now.difference(_aboveThresholdSince!).inMilliseconds >=
              _activationWindowMs) {
        state = DrivingMode.driving;
        appLog.i('[DrivingMode] → DRIVING (${kmh.toStringAsFixed(0)} km/h)');
      }
    } else if (kmh <= _stopThresholdKmh) {
      _aboveThresholdSince = null;
      _belowThresholdSince ??= now;
      if (state == DrivingMode.driving &&
          now.difference(_belowThresholdSince!).inMilliseconds >=
              _deactivationWindowMs) {
        state = DrivingMode.stationary;
        appLog.i('[DrivingMode] → STATIONARY');
      }
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }
}

/// Non-autoDispose: driving mode must persist for the full app session.
/// autoDispose would kill GPS tracking whenever the dashboard rebuilds.
final drivingModeProvider =
    StateNotifierProvider<DrivingModeService, DrivingMode>((ref) {
      return DrivingModeService();
    });
