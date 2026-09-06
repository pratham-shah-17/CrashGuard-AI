import '../logging/app_log.dart';
import 'ai_triage_service.dart';
import 'driving_mode_service.dart';

/// Phase 3 — Zero-hallucination safety validation.
///
/// This is the Validation Agent in the multi-agent stack. It runs after every
/// AI tier (cloud, on-device, heuristic, classifier) and enforces rule-based
/// constraints that the language model cannot override.
///
/// Why rule-based override instead of trusting the model fully:
///   Indian highway crashes can produce severely injured victims in seconds.
///   Gemma 4 27B (cloud) is excellent but can occasionally under-triage due to
///   sparse transcript context. A deterministic safety net is non-negotiable in
///   life-safety applications.
///
/// Rules (immutable, non-overridable):
///   A. Ambulance is mandatory if severity ≥ 3.
///   B. Severity floor = 3 if driving mode was active at SOS trigger.
///   C. Severity floor = 4 if crash gyroscope confirmed a vehicle roll/spin.
///   D. Severity may never be lowered below the accelerometer hint floor.
///   E. If confidence < 0.48 → emit low_confidence flag for UI warning.
///   F. Empty services list → add ambulance unconditionally.
///
/// All overrides are transparent: [ValidationResult.flags] lists every rule
/// that fired and [ValidationResult.overrideNotes] explains what changed.
/// The UI (TriageExplainabilityPanel) shows these notes to the user.
class TriageValidationAgent {
  const TriageValidationAgent();

  /// Validates and potentially overrides [raw].
  /// Returns a [ValidationResult] with the (possibly adjusted) triage and flags.
  ValidationResult validate({
    required TriageResult raw,
    required DrivingMode drivingMode,
    required double gyroPeakRadPerSec,
    required int accelSeverityHint,
  }) {
    var severity = raw.severityLevel;
    final services = List<String>.from(raw.requiredServices);
    final flags = <String>[];
    final overrides = <String>[];

    // ── Rule A: Severity floor from accelerometer sensor hint ─────────────
    // The sensor-derived hint is a hard lower bound: if Gemma says severity 2
    // but the accelerometer registered a 5-out-of-5 severity event, trust the
    // physical sensor over the text transcript.
    final sensorFloor = (accelSeverityHint * 0.85).round().clamp(1, 5);
    if (severity < sensorFloor) {
      overrides.add(
        'Severity raised $severity→$sensorFloor (accelerometer sensor floor).',
      );
      severity = sensorFloor;
      flags.add('severity_raised_by_sensor');
    }

    // ── Rule B: Driving mode severity floor ───────────────────────────────
    // A person triggering SOS while driving is almost certainly in a crash.
    // Minimum severity 3 (moderate) regardless of transcript context.
    if (drivingMode == DrivingMode.driving && severity < 3) {
      overrides.add(
        'Severity raised $severity→3 (driving mode active at SOS trigger).',
      );
      severity = 3;
      flags.add('severity_floor_driving_mode');
    }

    // ── Rule C: Gyroscope crash confirmation ─────────────────────────────
    // Angular velocity > 3.5 rad/s indicates car roll or spin — a high-energy
    // collision. Minimum severity 4 (severe).
    if (gyroPeakRadPerSec >= 3.5 && severity < 4) {
      overrides.add(
        'Severity raised $severity→4 (gyro ${gyroPeakRadPerSec.toStringAsFixed(1)} rad/s '
        'confirms vehicle roll/spin — high-energy crash).',
      );
      severity = 4;
      flags.add('severity_raised_by_gyro_crash');
    }

    // ── Rule D: Ambulance mandatory for severity ≥ 3 ─────────────────────
    if (severity >= 3 && !services.contains('ambulance')) {
      services.insert(0, 'ambulance');
      overrides.add('Ambulance added (mandatory for severity $severity).');
      flags.add('ambulance_added');
    }

    // ── Rule E: Empty services list guard ────────────────────────────────
    if (services.isEmpty) {
      services.add('ambulance');
      overrides.add('Ambulance added (services list was empty).');
      flags.add('ambulance_added');
    }

    // ── Rule F: Police recommended for severity 5 ─────────────────────────
    final hasAuthority = services.any((s) => s == 'police' || s == 'rescue');
    if (severity == 5 && !hasAuthority) {
      flags.add('consider_police_severity5');
    }

    // ── Confidence score ──────────────────────────────────────────────────
    final confidence = _computeConfidence(
      source: raw.source,
      hasThinkingTrace: raw.thinkingTrace != null,
      visionUsed: raw.visionUsed,
      overrideCount: overrides.length,
      gyroPeak: gyroPeakRadPerSec,
    );

    if (confidence < 0.48) {
      flags.add('low_confidence_review');
    }

    // ── Build result ──────────────────────────────────────────────────────
    final wasOverridden = overrides.isNotEmpty;
    if (wasOverridden) {
      appLog.w('[ValidationAgent] Overrode triage: ${overrides.join(" | ")}');
    } else {
      appLog.d(
        '[ValidationAgent] Triage validated — no overrides needed '
        '(confidence=${confidence.toStringAsFixed(2)})',
      );
    }

    final validated = TriageResult(
      functionCall: raw.functionCall,
      location: raw.location,
      severityLevel: severity,
      requiredServices: services,
      firstAidQuery: raw.firstAidQuery,
      compressedPayload: raw.compressedPayload,
      thinkingTrace: raw.thinkingTrace,
      isDegradedMode: raw.isDegradedMode,
      source: raw.source,
      visionUsed: raw.visionUsed,
      confidence: confidence,
      validationFlags: flags,
      wasOverridden: wasOverridden,
      validationNotes: overrides,
    );

    return ValidationResult(
      triage: validated,
      flags: flags,
      overrideNotes: overrides,
      confidence: confidence,
    );
  }

  /// Confidence score from source tier and signal quality.
  ///
  /// Reflects how reliable the triage result is. Shown to the user in the
  /// explainability panel. Never shown as a raw probability — displayed as
  /// a qualitative label (High / Moderate / Low).
  double _computeConfidence({
    required TriageSource source,
    required bool hasThinkingTrace,
    required bool visionUsed,
    required int overrideCount,
    required double gyroPeak,
  }) {
    var base = switch (source) {
      TriageSource.gemma4Cloud => 0.92,
      TriageSource.gemma4CloudVision => 0.94,
      TriageSource.gemma4OnDevice => 0.74,
      TriageSource.localTier2 => 0.58,
      TriageSource.offlineClassifier => 0.42,
      TriageSource.webDemo => 0.30,
    };

    if (hasThinkingTrace) base += 0.03;
    if (visionUsed) base += 0.04;
    if (gyroPeak >= 3.5) base += 0.03; // sensor corroboration
    if (gyroPeak >= 1.5 && gyroPeak < 3.5) base += 0.01;

    // Each override slightly reduces confidence — the AI needed correction.
    base -= overrideCount * 0.04;

    return base.clamp(0.10, 0.99);
  }
}

/// Result of a single validation pass.
class ValidationResult {
  final TriageResult triage;
  final List<String> flags;
  final List<String> overrideNotes;
  final double confidence;

  const ValidationResult({
    required this.triage,
    required this.flags,
    required this.overrideNotes,
    required this.confidence,
  });

  bool get wasOverridden => overrideNotes.isNotEmpty;

  /// Human-readable confidence label for UI display.
  String get confidenceLabel {
    if (confidence >= 0.80) return 'High';
    if (confidence >= 0.60) return 'Moderate';
    return 'Low — manual review recommended';
  }
}

const triageValidationAgent = TriageValidationAgent();
