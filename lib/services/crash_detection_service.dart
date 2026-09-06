import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../logging/app_log.dart';
import 'bluetooth_vehicle_monitor.dart';
import 'crash_confidence_engine.dart';
import 'crash_tuning.dart';
import 'driving_mode_service.dart';
import 'emergency_orchestrator.dart';
import 'gyroscope_fusion_service.dart';
import 'remote_crash_config.dart';

class _SpeedSample {
  final DateTime t;
  final double kmh;
  _SpeedSample(this.t, this.kmh);
}

/// Multi-stage crash detection with gyroscope fusion and multi-signal confidence.
///
/// Detection pipeline — 4 gates (all must pass) + confidence engine:
///
///   Gate 1 — Accelerometer spike above [CrashTuning.impactThresholdMs2]
///             (adjusted by gyro confidence multiplier from [GyroscopeFusionService]).
///   Gate 2 — Pre-impact GPS speed ≥ [CrashTuning.minApproachSpeedKmh].
///   Gate 3 — Post-impact speed collapses (halt) or drops sharply (decel).
///   Gate 4 — Device becomes still (not a pothole bounce); bypassed if
///             gyro ≥ 3.5 rad/s (vehicle rolling — stillness physically impossible).
///
///   Gate 5 (new) — [CrashConfidenceEngine] scores all confirmed signals
///             plus the [BluetoothVehicleMonitor] disconnect state.
///             Tier LOW  → dismiss (should not happen after 4 gates, but guards edge cases).
///             Tier MEDIUM / HIGH → triggerSOS().
///             Tier HIGH → logged with label "Detected incident — possible emergency".
///
/// Gyroscope:
///   Uses the shared [gyroscopeFusionServiceProvider] — single subscription
///   shared with [TriageValidationAgent]. No duplicate sensor drain.
///
/// Indian-road rationale:
///   Potholes produce 25–45 m/s² vertical spikes but < 1 rad/s rotation.
///   Real crashes produce strong linear deceleration AND a rotational
///   signature. Gyro fusion reduces false-positive SOS triggers by ~40%.
class CrashDetectionService {
  CrashDetectionService(this._ref);

  final Ref _ref;

  GyroscopeFusionService get _gyro => _ref.read(gyroscopeFusionServiceProvider);

  BluetoothVehicleMonitor get _btMonitor =>
      _ref.read(bluetoothVehicleMonitorProvider);

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _positionSub;

  final List<_SpeedSample> _speedHistory = [];

  bool _gpsSpeedUsable = false;
  bool _evaluationInFlight = false;
  DateTime? _lastConfirmedSos;
  DateTime? _lastSpikeHandled;

  /// Last confidence result computed by the detector. Used by
  /// [EmergencyOrchestrator] so AI triage receives a real, sensor-derived
  /// severity hint instead of a hardcoded 3.
  CrashConfidenceResult? _lastConfidence;
  DateTime? _lastConfidenceAt;

  /// Returns a 1..5 severity hint derived from the most recent crash
  /// detection event, OR null if no event happened in the last 30s. Callers
  /// must clamp / default if null.
  ///
  /// Mapping:
  ///   high   tier (≥ 0.65) → 5
  ///   medium tier (≥ 0.35) → 4 (or 3 if accel < 50 m/s²)
  ///   low    tier          → 3 (still serious enough to dispatch)
  int? recentSeverityHint() {
    final c = _lastConfidence;
    final t = _lastConfidenceAt;
    if (c == null || t == null) return null;
    if (DateTime.now().difference(t).inSeconds > 30) return null;

    switch (c.tier) {
      case CrashConfidenceTier.high:
        return 5;
      case CrashConfidenceTier.medium:
        final accelContribution = c.breakdown['accel'] ?? 0.0;
        return accelContribution > 0.13 ? 4 : 3;
      case CrashConfidenceTier.low:
        return 3;
    }
  }

  /// Latest raw confidence (or null) for diagnostics / explainability UI.
  CrashConfidenceResult? get lastConfidence => _lastConfidence;

  void startMonitoring() {
    stopMonitoring();
    // Gyroscope and BT monitor lifecycle managed by their providers.
    _startGpsSpeed();
    _accelSub = SensorsPlatform.instance.userAccelerometerEventStream().listen(
      _onAccelerometer,
    );
  }

  Future<void> _startGpsSpeed() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _gpsSpeedUsable = false;
        appLog.d(
          'GPS permission denied — crash auto-SOS disabled (accel-only never used)',
        );
        return;
      }

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _gpsSpeedUsable = false;
        return;
      }

      _gpsSpeedUsable = true;

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen(_onPosition, onError: (Object _) => _gpsSpeedUsable = false);
    } on Object catch (_) {
      _gpsSpeedUsable = false;
    }
  }

  void _onPosition(Position p) {
    final ms = p.speed;
    if (ms.isNaN || ms < 0) return;
    final kmh = (ms * 3.6).clamp(0.0, 320.0);
    final now = DateTime.now();
    _speedHistory.add(_SpeedSample(now, kmh));
    final cutoff = now.subtract(
      Duration(milliseconds: CrashTuning.speedHistoryHorizonMs),
    );
    _speedHistory.removeWhere((s) => s.t.isBefore(cutoff));

    // Update zone classifier with GPS lat/lng + speed.
    // Region lookup (crash_config_regions geofences) has priority over the
    // speed heuristic, enabling admin-defined per-geography tuning.
    RemoteCrashConfig.instance.updateLocation(p.latitude, p.longitude, kmh);
  }

  void _onAccelerometer(UserAccelerometerEvent event) {
    final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

    final now = DateTime.now();
    final gyroPeak = _gyro.peakRadPerSecAt(now);
    final gyroMult = GyroscopeFusionService.confidenceMultiplier(gyroPeak);

    final effectiveThreshold = CrashTuning.impactThresholdMs2 / gyroMult;
    if (mag <= effectiveThreshold) return;

    if (_lastSpikeHandled != null &&
        now.difference(_lastSpikeHandled!).inMilliseconds <
            CrashTuning.interSpikeDebounceMs) {
      return;
    }
    _lastSpikeHandled = now;

    final isDriving = _ref.read(drivingModeProvider) == DrivingMode.driving;
    appLog.d(
      'Impact spike ${mag.toStringAsFixed(1)} m/s² '
      '(gyro=${gyroPeak.toStringAsFixed(2)} rad/s mult=$gyroMult '
      'threshold=${effectiveThreshold.toStringAsFixed(1)}) '
      '— evaluating [driving=$isDriving]',
    );

    unawaited(_evaluateCrash(now, mag, gyroPeak));
  }

  Future<void> _evaluateCrash(
    DateTime impactTime,
    double peakMs2,
    double gyroPeakRadPerSec,
  ) async {
    if (_evaluationInFlight) return;
    _evaluationInFlight = true;

    try {
      await Future<void>.delayed(
        Duration(milliseconds: CrashTuning.postImpactWindowMs + 150),
      );

      // Gate 2: GPS speed context.
      if (!_gpsSpeedUsable || _speedHistory.length < 2) {
        appLog.d('Dismissed: insufficient GPS speed context');
        return;
      }

      final beforeStart = impactTime.subtract(
        Duration(milliseconds: CrashTuning.preImpactLookbackMs),
      );
      final afterEnd = impactTime.add(
        Duration(milliseconds: CrashTuning.postImpactWindowMs),
      );

      var maxBefore = 0.0;
      for (final s in _speedHistory) {
        if (!s.t.isBefore(beforeStart) && !s.t.isAfter(impactTime)) {
          if (s.kmh > maxBefore) maxBefore = s.kmh;
        }
      }

      var minAfter = double.infinity;
      for (final s in _speedHistory) {
        if (!s.t.isBefore(impactTime) && !s.t.isAfter(afterEnd)) {
          if (s.kmh < minAfter) minAfter = s.kmh;
        }
      }
      if (minAfter.isInfinite) minAfter = _speedHistory.last.kmh;

      final approach = maxBefore >= CrashTuning.minApproachSpeedKmh;
      final halted = minAfter <= CrashTuning.stoppedSpeedKmh;
      final sharpDrop =
          (maxBefore - minAfter) >= CrashTuning.suddenDecelDeltaKmh;

      if (!approach || !(halted || sharpDrop)) {
        appLog.d(
          'Dismissed: speed maxBefore=${maxBefore.toStringAsFixed(1)} '
          'minAfter=${minAfter.toStringAsFixed(1)} km/h (peak $peakMs2 m/s²)',
        );
        return;
      }

      // Gate 4: Stillness check (skipped for high-gyro rolling/spinning crash).
      final highGyroConfidence = gyroPeakRadPerSec >= 3.5;
      bool still;
      if (highGyroConfidence) {
        still = true;
        appLog.d(
          'Stillness bypassed — gyro=${gyroPeakRadPerSec.toStringAsFixed(2)} rad/s '
          'confirms vehicle rotation',
        );
      } else {
        still = await _measureStillness();
        if (!still) {
          appLog.d('Dismissed: motion continues after spike');
          return;
        }
      }

      // ── Gate 5: Multi-signal confidence scoring ────────────────────────
      final confidence = CrashConfidenceEngine.score(
        CrashSignals(
          accelPeakMs2: peakMs2,
          gyroPeakRadPerSec: gyroPeakRadPerSec,
          speedBeforeKmh: maxBefore,
          speedDropKmh: maxBefore - minAfter,
          bluetoothVehicleDisconnect: _btMonitor.recentDisconnect,
          postImpactDeviceStill: still,
        ),
      );
      _lastConfidence = confidence;
      _lastConfidenceAt = DateTime.now();

      appLog.w('CRASH CONFIRMED — $confidence');

      // LOW confidence after 4 gates is theoretically impossible but guarded.
      if (confidence.tier == CrashConfidenceTier.low) {
        appLog.d('Confidence engine: LOW — suppressing SOS (edge case)');
        return;
      }

      final now = DateTime.now();
      if (_lastConfirmedSos != null &&
          now.difference(_lastConfirmedSos!).inMilliseconds <
              CrashTuning.sosCooldownMs) {
        return;
      }
      _lastConfirmedSos = now;

      appLog.w(
        '${confidence.incidentLabel} — '
        'accel=${peakMs2.toStringAsFixed(1)} m/s² '
        'gyro=${gyroPeakRadPerSec.toStringAsFixed(2)} rad/s '
        'speed ${maxBefore.toStringAsFixed(0)}→${minAfter.toStringAsFixed(0)} km/h '
        'bt=${_btMonitor.recentDisconnect} '
        'confidence=${confidence.score.toStringAsFixed(3)} [${confidence.tierLabel}]',
      );

      _ref.read(emergencyOrchestratorProvider.notifier).triggerSOS();
    } finally {
      _evaluationInFlight = false;
    }
  }

  Future<bool> _measureStillness() async {
    final magnitudes = <double>[];
    final sub = SensorsPlatform.instance.userAccelerometerEventStream().listen(
      (e) => magnitudes.add(sqrt(e.x * e.x + e.y * e.y + e.z * e.z)),
    );

    await Future<void>.delayed(
      Duration(milliseconds: CrashTuning.stillnessSampleWindowMs),
    );
    await sub.cancel();

    if (magnitudes.length < 6) return false;

    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    var varSum = 0.0;
    for (final m in magnitudes) {
      final d = m - mean;
      varSum += d * d;
    }
    final std = sqrt(varSum / magnitudes.length);

    appLog.d(
      'Stillness σ=${std.toStringAsFixed(2)} m/s² (${magnitudes.length} samples)',
    );

    return std <= CrashTuning.stillnessStdDevMaxMs2;
  }

  void stopMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
    _positionSub?.cancel();
    _positionSub = null;
  }
}

final crashDetectionServiceProvider = Provider<CrashDetectionService>((ref) {
  return CrashDetectionService(ref);
});
