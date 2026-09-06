import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manually-entered vital signs for bystander triage assistance.
///
/// SOURCE IS ALWAYS 'manual' — these are numbers a bystander reads/estimates
/// and enters. This is NOT camera-based rPPG or wearable data.
/// It exists to help bystanders communicate vitals to phone dispatchers.
class VitalSigns {
  final int bpm;
  final int respiratoryRate;
  final double bloodOxygen;
  final String interpretation;
  final DateTime recordedAtUtc;

  /// Always 'manual' — values entered by a bystander, not from a sensor.
  final String source;

  VitalSigns({
    required this.bpm,
    required this.respiratoryRate,
    required this.bloodOxygen,
    required this.interpretation,
    required this.recordedAtUtc,
    this.source = 'manual',
  });
}

/// Bystander vital signs logger.
/// Stores manually-entered pulse, respiration, and SpO2 readings.
///
/// IMPORTANT: These values are manually entered by a bystander — NOT
/// measured by the phone camera or sensors. The app displays these values
/// to help relay information to emergency dispatchers (108/112).
class VitalSignsLogger extends StateNotifier<VitalSigns?> {
  VitalSignsLogger() : super(null);

  /// Records manually-entered vital sign observations.
  /// All three parameters must be provided by the bystander directly.
  void recordManual({
    required int bpm,
    required int respiratoryRate,
    required double bloodOxygen,
  }) {
    final interpretation = _interpretForDispatch(
      bpm: bpm,
      respiratoryRate: respiratoryRate,
      bloodOxygen: bloodOxygen,
    );
    state = VitalSigns(
      bpm: bpm,
      respiratoryRate: respiratoryRate,
      bloodOxygen: bloodOxygen,
      interpretation: interpretation,
      recordedAtUtc: DateTime.now().toUtc(),
      source: 'manual',
    );
  }

  /// Produces a dispatcher-ready summary for relay to 108/112 operators.
  String? get dispatcherSummary {
    if (state == null) return null;
    final v = state!;
    return 'Vitals (bystander-observed): '
        'HR=${v.bpm}bpm RR=${v.respiratoryRate}/min SpO2=${v.bloodOxygen.toStringAsFixed(0)}% '
        '— ${v.interpretation}';
  }

  /// Alias used by VitalScanScreen.
  void setManual({
    required int bpm,
    required int respiratoryRate,
    required double bloodOxygen,
  }) => recordManual(
    bpm: bpm,
    respiratoryRate: respiratoryRate,
    bloodOxygen: bloodOxygen,
  );

  void clear() => state = null;

  String _interpretForDispatch({
    required int bpm,
    required int respiratoryRate,
    required double bloodOxygen,
  }) {
    final flags = <String>[];
    if (bpm >= 120) flags.add('tachycardia (very fast pulse)');
    if (bpm <= 45) flags.add('bradycardia (very slow pulse)');
    if (respiratoryRate >= 24) flags.add('tachypnoea (rapid breathing)');
    if (respiratoryRate <= 8) flags.add('bradypnoea (slow breathing)');
    if (bloodOxygen < 90) flags.add('hypoxia (SpO2 <90% — CRITICAL)');
    if (bloodOxygen >= 90 && bloodOxygen < 94) {
      flags.add('borderline oxygen (SpO2 90-93%)');
    }

    if (flags.isEmpty) {
      return 'No immediately critical vital signs from bystander observation.';
    }
    return 'CRITICAL FLAGS: ${flags.join(', ')}. '
        'Treat as high severity. Call 108/112 now if not done.';
  }
}

// Keep backward-compatible alias used by existing UI code.
typedef VitalSignsService = VitalSignsLogger;

final vitalSignsProvider =
    StateNotifierProvider.autoDispose<VitalSignsLogger, VitalSigns?>((ref) {
      return VitalSignsLogger();
    });
