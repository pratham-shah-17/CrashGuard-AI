import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_log.dart';

/// Phase 8 — Bounded preference calibration (NOT reinforcement learning).
///
/// Earlier docs called this "RL-based optimisation" — the implementation is
/// an exponential moving average over a user-supplied severity bias, never
/// touches model weights, and is bounded to [-1.0, +1.0]. Use the more
/// accurate term "preference calibration" in new docs and READMEs.
///
/// After an SOS is resolved the user is shown a two-question prompt:
///   Q1. "Was the severity estimate correct?"  (too low / just right / too high)
///   Q2. "Were the right services called?"    (yes / some were missing / unnecessary)
///
/// Feedback drives a [severityBias] (range −1.0..+1.0) that adjusts the
/// Tier 3 and Tier 4 offline classifiers. Cloud and on-device Gemma tiers
/// are NOT affected — they produce calibrated output already.
///
/// Learning constraints (making it safe and bounded):
///   - Bias is bounded to [−1.0, +1.0] — cannot drift to extremes.
///   - Minimum 3 feedback samples before any bias is applied.
///   - Each new sample carries only 15% weight (exponential moving average).
///   - The bias is visible to the user in Settings and fully resettable.
///   - No model weights are modified — this is preference calibration only.
class TriageFeedbackService {
  TriageFeedbackService._();
  static final instance = TriageFeedbackService._();

  static const _kBias = 'triage_severity_bias';
  static const _kCount = 'triage_feedback_count';
  static const _kHistory = 'triage_feedback_history';
  static const _kAlpha = 0.15; // EMA learning rate
  static const _kMinSamples = 3; // No bias until 3 feedbacks collected
  static const _kMaxHistory = 20;

  double _bias = 0.0;
  int _count = 0;

  /// How many severity levels to shift Tier 3/4 output.
  /// Positive = inflate; negative = deflate.
  double get severityBias => _count >= _kMinSamples ? _bias : 0.0;

  int get feedbackCount => _count;

  bool get isLearningActive => _count >= _kMinSamples;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _bias = prefs.getDouble(_kBias) ?? 0.0;
    _count = prefs.getInt(_kCount) ?? 0;
    appLog.d(
      '[Feedback] RL bias=${_bias.toStringAsFixed(2)} n=$_count '
      '(active=$isLearningActive)',
    );
  }

  /// Record user feedback for a completed SOS.
  ///
  /// [severityDelta]: -1 = AI was too high, 0 = correct, +1 = AI was too low.
  /// [servicesCorrect]: true if the called services matched the actual need.
  Future<void> recordFeedback({
    required String incidentId,
    required int severityDelta,
    required bool servicesCorrect,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // EMA update: bias moves 15% toward the new signal each time.
    _bias = (_bias * (1.0 - _kAlpha) + severityDelta * _kAlpha).clamp(
      -1.0,
      1.0,
    );
    _count++;

    await prefs.setDouble(_kBias, _bias);
    await prefs.setInt(_kCount, _count);

    // Append to bounded history for Settings audit trail.
    final rawHistory = prefs.getString(_kHistory);
    final history = rawHistory != null
        ? List<Map<String, dynamic>>.from(
            (jsonDecode(rawHistory) as List).cast<Map<String, dynamic>>(),
          )
        : <Map<String, dynamic>>[];

    history.add({
      'id': incidentId,
      'ts': DateTime.now().toIso8601String(),
      'severity_delta': severityDelta,
      'services_correct': servicesCorrect,
    });

    if (history.length > _kMaxHistory) {
      history.removeRange(0, history.length - _kMaxHistory);
    }
    await prefs.setString(_kHistory, jsonEncode(history));

    appLog.i(
      '[Feedback] Recorded: delta=$severityDelta services_ok=$servicesCorrect '
      '→ bias=${_bias.toStringAsFixed(2)} (n=$_count)',
    );
  }

  /// Apply the learned bias to a raw severity score.
  /// Only called by Tier 3 and Tier 4 classifiers.
  int applyBias(int rawSeverity) {
    if (!isLearningActive) return rawSeverity;
    final adjusted = (rawSeverity + _bias).round().clamp(1, 5);
    if (adjusted != rawSeverity) {
      appLog.d(
        '[Feedback] Bias applied: $rawSeverity → $adjusted '
        '(bias=${_bias.toStringAsFixed(2)})',
      );
    }
    return adjusted;
  }

  /// Reset all learning — called from Settings.
  Future<void> resetBias() async {
    _bias = 0.0;
    _count = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBias);
    await prefs.remove(_kCount);
    await prefs.remove(_kHistory);
    appLog.i('[Feedback] RL bias reset to zero.');
  }

  /// Audit history for Settings screen.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistory);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).cast<Map<String, dynamic>>(),
    );
  }
}
