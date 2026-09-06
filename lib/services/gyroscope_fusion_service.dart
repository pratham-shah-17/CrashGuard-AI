import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../logging/app_log.dart';

/// Tracks gyroscope angular velocity over a rolling window.
///
/// During a real vehicle collision, angular velocity typically exceeds 3–4 rad/s
/// (the car rotates, rolls, or spins). A pothole produces < 1.5 rad/s because
/// the vehicle bounces vertically without significant angular change.
///
/// Used by [CrashDetectionService] to compute a gyro-augmented confidence score:
/// - gyro peak > 3.5 rad/s → crash signature (car roll / spin)
/// - gyro peak 1.5–3.5 rad/s → ambiguous — normal evaluation continues
/// - gyro peak < 1.5 rad/s → pothole / phone-drop — raise effective threshold
///
/// Degrades gracefully: if the device has no gyroscope or the stream fails,
/// [peakRadPerSecAt] returns 0.0 and crash detection falls back to
/// accel-only mode (unchanged from before this service existed).
class GyroscopeFusionService {
  static const int _horizonMs = 3000;

  StreamSubscription<GyroscopeEvent>? _sub;
  final List<_GyroSample> _samples = [];

  bool _available = false;
  bool get isAvailable => _available;

  void startTracking() {
    _sub?.cancel();
    try {
      _sub = SensorsPlatform.instance.gyroscopeEventStream().listen(
        _onGyro,
        onError: (Object _) {
          _available = false;
        },
      );
      _available = true;
      appLog.d('[Gyro] Gyroscope fusion tracking started');
    } on Object catch (e) {
      _available = false;
      appLog.d('[Gyro] Gyroscope unavailable on this device: $e');
    }
  }

  void stopTracking() {
    _sub?.cancel();
    _sub = null;
    _samples.clear();
    _available = false;
  }

  void _onGyro(GyroscopeEvent e) {
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final now = DateTime.now();
    _samples.add(_GyroSample(now, mag));
    final cutoff = now.subtract(const Duration(milliseconds: _horizonMs));
    _samples.removeWhere((s) => s.t.isBefore(cutoff));
  }

  /// Returns the peak angular velocity (rad/s) in the [windowMs] preceding [at].
  /// Returns 0.0 if no gyroscope data is available (graceful degradation).
  double peakRadPerSecAt(DateTime at, {int windowMs = 1500}) {
    if (_samples.isEmpty) return 0.0;
    final from = at.subtract(Duration(milliseconds: windowMs));
    var peak = 0.0;
    for (final s in _samples) {
      if (!s.t.isBefore(from) && !s.t.isAfter(at)) {
        if (s.radPerSec > peak) peak = s.radPerSec;
      }
    }
    return peak;
  }

  /// Converts a gyro peak reading to a crash confidence multiplier.
  ///
  /// Returns a value in [0.6 .. 1.4]:
  /// - 1.4 → strong angular signature (car roll / spin) — lower effective accel threshold
  /// - 1.0 → ambiguous → standard evaluation
  /// - 0.6 → low rotation → likely pothole / phone-drop → raise effective threshold
  static double confidenceMultiplier(double peakRadPerSec) {
    if (peakRadPerSec >= 3.5) return 1.4;
    if (peakRadPerSec >= 2.0) return 1.2;
    if (peakRadPerSec >= 1.5) return 1.0;
    if (peakRadPerSec >= 0.8) return 0.85;
    if (peakRadPerSec > 0.0) return 0.6;
    return 1.0; // No gyro data — neutral (backward-compatible)
  }
}

class _GyroSample {
  final DateTime t;
  final double radPerSec;
  const _GyroSample(this.t, this.radPerSec);
}

/// Non-autoDispose: gyro history must survive widget rebuilds so the crash peak
/// recorded at SOS trigger is still readable when the validation agent runs
/// a few seconds later during GPS lock + triage.
final gyroscopeFusionServiceProvider = Provider<GyroscopeFusionService>((ref) {
  final svc = GyroscopeFusionService();
  svc.startTracking();
  ref.onDispose(svc.stopTracking);
  return svc;
});
