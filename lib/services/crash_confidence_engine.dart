/// Phase 1 / Phase 7 — Multi-signal crash confidence engine.
///
/// Aggregates all available sensor and contextual signals into a single
/// normalised score in [0.0, 1.0] and maps it to a [CrashConfidenceTier].
///
/// Signal weights (must sum to 1.0):
///   accel peak          0.30  — primary impact signature
///   gyro peak           0.22  — vehicle rotation signature
///   speed before        0.20  — confirms vehicle was moving
///   speed drop          0.15  — confirms sudden deceleration
///   BT disconnect       0.08  — vehicle infotainment dropped (Phase 6)
///   post-impact still   0.05  — driver unresponsive (Phase 1)
///
/// Confidence tiers:
///   LOW    < 0.35  — log only; no user action
///   MEDIUM 0.35–0.64 — prompt user (existing countdown); could be a pothole
///   HIGH   ≥ 0.65 — high-precision crash; auto-SOS if user non-responsive
///
/// Design constraint (Phase 7 / brief):
///   The engine NEVER labels the incident as "accident" or guesses cause.
///   All logs and downstream consumers receive the factual label
///   "Detected incident — possible emergency" only.
library;

/// Raw input signals for one evaluation cycle.
class CrashSignals {
  /// Peak user-acceleration magnitude in m/s² (Vector3 magnitude).
  final double accelPeakMs2;

  /// Peak angular velocity from [GyroscopeFusionService] in rad/s.
  final double gyroPeakRadPerSec;

  /// Maximum GPS speed in km/h recorded in the 2s before the accel spike.
  final double speedBeforeKmh;

  /// Speed drop in km/h between pre-impact max and post-impact min.
  final double speedDropKmh;

  /// True if a Bluetooth device (likely car infotainment) disconnected within
  /// the last 30 seconds while the vehicle was moving.
  final bool bluetoothVehicleDisconnect;

  /// True if the device has been still for longer than [inactivityThresholdSec]
  /// after the impact — driver may be incapacitated.
  final bool postImpactDeviceStill;

  const CrashSignals({
    required this.accelPeakMs2,
    required this.gyroPeakRadPerSec,
    required this.speedBeforeKmh,
    required this.speedDropKmh,
    this.bluetoothVehicleDisconnect = false,
    this.postImpactDeviceStill = true,
  });
}

enum CrashConfidenceTier {
  /// < 0.35 — do not trigger; log for analytics only.
  low,

  /// 0.35–0.64 — show user confirmation window (countdown + cancel).
  medium,

  /// ≥ 0.65 — high-precision event; trigger SOS if user non-responsive.
  high,
}

class CrashConfidenceResult {
  final double score;
  final CrashConfidenceTier tier;
  final Map<String, double> breakdown;

  const CrashConfidenceResult({
    required this.score,
    required this.tier,
    required this.breakdown,
  });

  String get tierLabel => switch (tier) {
    CrashConfidenceTier.low => 'LOW',
    CrashConfidenceTier.medium => 'MEDIUM',
    CrashConfidenceTier.high => 'HIGH',
  };

  /// Factual, non-speculative label for emergency messaging (Phase 7 constraint).
  String get incidentLabel => tier == CrashConfidenceTier.high
      ? 'Detected incident — possible emergency'
      : 'Possible incident detected';

  @override
  String toString() =>
      'CrashConfidence[$tierLabel score=${score.toStringAsFixed(3)}] '
      '${breakdown.entries.map((e) => '${e.key}=${e.value.toStringAsFixed(2)}').join(' ')}';
}

abstract final class CrashConfidenceEngine {
  CrashConfidenceEngine._();

  // ── Weight constants ──────────────────────────────────────────────────────

  static const double _wAccel = 0.30;
  static const double _wGyro = 0.22;
  static const double _wSpeed = 0.20;
  static const double _wDrop = 0.15;
  static const double _wBt = 0.08;
  static const double _wStill = 0.05;

  // ── Normalisation reference maxima ────────────────────────────────────────

  /// Accel normalised against 120 m/s² (severe but survivable crash reference).
  static const double _accelMax = 120.0;

  /// Gyro normalised against 8 rad/s (vehicle roll / high-speed spin cap).
  static const double _gyroMax = 8.0;

  /// Speed reference: 120 km/h highway limit (India NH).
  static const double _speedMax = 120.0;

  /// Drop reference: full speed-to-zero scenario.
  static const double _dropMax = 120.0;

  // ── Tier thresholds ───────────────────────────────────────────────────────

  static const double _mediumThreshold = 0.35;
  static const double _highThreshold = 0.65;

  /// Compute a confidence score from raw sensor signals.
  ///
  /// All inputs are clamped before normalisation; no NaN or negative values
  /// will cause undefined behaviour.
  static CrashConfidenceResult score(CrashSignals s) {
    // Per-signal normalised contributions (each in [0.0, 1.0]).
    final accelN = (s.accelPeakMs2.clamp(0.0, _accelMax) / _accelMax);
    final gyroN = (s.gyroPeakRadPerSec.clamp(0.0, _gyroMax) / _gyroMax);
    final speedN = (s.speedBeforeKmh.clamp(0.0, _speedMax) / _speedMax);
    final dropN = (s.speedDropKmh.clamp(0.0, _dropMax) / _dropMax);
    final btN = s.bluetoothVehicleDisconnect ? 1.0 : 0.0;
    final stillN = s.postImpactDeviceStill ? 1.0 : 0.0;

    final raw =
        accelN * _wAccel +
        gyroN * _wGyro +
        speedN * _wSpeed +
        dropN * _wDrop +
        btN * _wBt +
        stillN * _wStill;

    final clamped = raw.clamp(0.0, 1.0);

    final tier = clamped >= _highThreshold
        ? CrashConfidenceTier.high
        : clamped >= _mediumThreshold
        ? CrashConfidenceTier.medium
        : CrashConfidenceTier.low;

    return CrashConfidenceResult(
      score: clamped,
      tier: tier,
      breakdown: {
        'accel': accelN * _wAccel,
        'gyro': gyroN * _wGyro,
        'speed': speedN * _wSpeed,
        'drop': dropN * _wDrop,
        'bt': btN * _wBt,
        'still': stillN * _wStill,
      },
    );
  }
}
