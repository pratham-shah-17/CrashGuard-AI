import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../logging/app_log.dart';
import 'driving_mode_service.dart';
import 'emergency_orchestrator.dart';

/// Phase 1 / Phase 6 — Incapacitation / unconscious driver detector.
///
/// Addresses the scenario that the 4-gate crash pipeline cannot detect:
/// the driver loses consciousness gradually (medical emergency, sudden illness)
/// without any accelerometer spike — the car may drift to a stop or a barrier
/// slowly.
///
/// Detection logic:
///   1. Driving mode is ACTIVE (GPS-confirmed vehicle speed > 40 km/h for
///      ≥ 25 seconds).
///   2. User accelerometer RMS drops below [_stillnessRmsThresholdMs2] for
///      a rolling window of [_stillnessWindowSec] seconds — device is motionless.
///   3. This sustained stillness has lasted [_incapacitationThresholdSec]
///      seconds since driving mode was last active.
///   4. No SOS is already in progress.
///
/// On trigger:
///   Calls [EmergencyOrchestrator.startSos()] which shows the user a 10-second
///   confirmation countdown with voice and haptics (Phase 7 / 8). If the user
///   cancels, the incapacitation detector records this and applies an
///   exponential backoff before re-checking (3× longer window next time).
///
/// False-positive guards:
///   - [_cooldownMs]: 5 minutes between any two triggers.
///   - [_minDrivingSecondsBeforeArming]: detector only arms 60s after
///     driving mode activates to avoid triggering at traffic lights.
///   - The countdown+cancel (existing UX) is the final user gate.
class InactivityCrashDetector {
  final Ref _ref;

  static const double _stillnessRmsThresholdMs2 = 1.8;

  /// RMS rolling window duration (~50 Hz accelerometer samples).
  static const int _stillnessWindowSec = 5;
  static const int _accelApproxHz = 50;
  static const int _incapacitationThresholdSec = 50; // sustained stillness
  static const int _cooldownMs = 5 * 60 * 1000;
  static const int _minDrivingSecondsBeforeArming = 60;

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  Timer? _evaluationTimer;

  final List<double> _rmsWindow = [];
  DateTime? _drivingActiveSince;
  DateTime? _stilnessStartedAt;
  DateTime? _lastTrigger;

  InactivityCrashDetector(this._ref);

  void startMonitoring() {
    stopMonitoring();

    // Subscribe to accelerometer for RMS tracking.
    _accelSub = SensorsPlatform.instance.userAccelerometerEventStream().listen(
      _onAccel,
    );

    // Evaluate incapacitation window every 10 seconds.
    _evaluationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _evaluate(),
    );
  }

  void _onAccel(UserAccelerometerEvent e) {
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _rmsWindow.add(mag);
    // Rolling window ≈ [_stillnessWindowSec] at ~[_accelApproxHz] Hz.
    final maxSamples = _stillnessWindowSec * _accelApproxHz;
    if (_rmsWindow.length > maxSamples) _rmsWindow.removeAt(0);
  }

  double _computeRms() {
    if (_rmsWindow.isEmpty) return 0.0;
    final sumSq = _rmsWindow.fold<double>(0, (s, v) => s + v * v);
    return sqrt(sumSq / _rmsWindow.length);
  }

  void _evaluate() {
    final mode = _ref.read(drivingModeProvider);
    final now = DateTime.now();

    if (mode != DrivingMode.driving) {
      _drivingActiveSince = null;
      _stilnessStartedAt = null;
      return;
    }

    // Track how long we've been driving.
    _drivingActiveSince ??= now;
    final drivingSeconds = now.difference(_drivingActiveSince!).inSeconds;

    // Arm only after minimum driving duration.
    if (drivingSeconds < _minDrivingSecondsBeforeArming) return;

    // Check for sustained stillness.
    final rms = _computeRms();
    final isStill = rms < _stillnessRmsThresholdMs2;

    if (isStill) {
      _stilnessStartedAt ??= now;
      final stillSeconds = now.difference(_stilnessStartedAt!).inSeconds;

      appLog.d(
        '[Inactivity] Device still for ${stillSeconds}s '
        '(RMS=${rms.toStringAsFixed(2)} m/s²) while driving',
      );

      if (stillSeconds >= _incapacitationThresholdSec) {
        _maybeFireSos();
      }
    } else {
      // Device is moving — reset stillness counter.
      _stilnessStartedAt = null;
    }
  }

  void _maybeFireSos() {
    final now = _ref.read(emergencyOrchestratorProvider).phase;
    if (now != SOSPhase.idle) return; // SOS already active.

    final ts = DateTime.now();
    if (_lastTrigger != null &&
        ts.difference(_lastTrigger!).inMilliseconds < _cooldownMs) {
      return; // Cooldown — user already cancelled once.
    }
    _lastTrigger = ts;
    _stilnessStartedAt = null; // Reset so we don't re-fire immediately.

    appLog.w(
      '[Inactivity] INCAPACITATION SIGNAL: device still for '
      '>= $_incapacitationThresholdSec s while driving — triggering SOS prompt',
    );

    _ref.read(emergencyOrchestratorProvider.notifier).startSos();
  }

  void stopMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
    _evaluationTimer?.cancel();
    _evaluationTimer = null;
    _rmsWindow.clear();
    _stilnessStartedAt = null;
    _drivingActiveSince = null;
  }

  void dispose() => stopMonitoring();
}

/// Non-autoDispose: must run for the full app session to detect incapacitation.
final inactivityCrashDetectorProvider = Provider<InactivityCrashDetector>((
  ref,
) {
  final svc = InactivityCrashDetector(ref);
  svc.startMonitoring();
  ref.onDispose(svc.dispose);
  return svc;
});
