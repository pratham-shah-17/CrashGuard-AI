/// Tier-2 local triage model (lightweight, deterministic, offline).
///
/// This intentionally sits between:
/// - Tier 3: very simple keyword heuristic ([OfflineTriageClassifier])
/// - Tier 1: cloud LLM triage (server-side Gemma 4 27B via Supabase Edge Function)
///
/// Tier-2 is designed to be replaceable by a small TFLite/ONNX model later while
/// keeping the same output contract.
class Tier2LocalTriageModel {
  const Tier2LocalTriageModel();

  Tier2LocalTriage classify({
    required String transcript,
    required int severityHint,
  }) {
    final t = transcript.toLowerCase();
    final h = severityHint.clamp(1, 5);

    // Weighted scoring: tries to reduce false-low severity while staying deterministic.
    var score = 0;

    // Life-threatening indicators.
    if (_hasAny(t, const ['not breathing', 'no pulse', 'cardiac arrest'])) {
      score += 8;
    }
    if (_hasAny(t, const ['unconscious', 'passed out', 'unresponsive'])) {
      score += 6;
    }
    if (_hasAny(t, const ['bleeding heavily', 'severe bleeding', 'spurting'])) {
      score += 6;
    }
    if (_hasAny(t, const ['trapped', 'pinned', 'stuck in vehicle'])) {
      score += 6;
    }

    // Major trauma / dangerous context.
    if (_hasAny(t, const ['head injury', 'concussion', 'seizure'])) score += 4;
    if (_hasAny(t, const ['fracture', 'broken', 'open wound'])) score += 3;
    if (_hasAny(t, const ['fire', 'smoke', 'burning', 'explosion'])) score += 5;

    // Moderate indicators.
    if (_hasAny(t, const ['pain', 'hurt', 'bleeding', 'crash', 'accident'])) {
      score += 2;
    }

    // Hint from crash detection (1-5): amplify but do not let it dominate fully.
    score += (h - 1) * 2;

    final severity = _scoreToSeverity(score);
    final services = _servicesFromText(t);
    final aid = _firstAidQueryFromText(t);

    return Tier2LocalTriage(
      severityLevel: severity,
      requiredServices: services,
      firstAidQuery: aid,
    );
  }

  int _scoreToSeverity(int score) {
    if (score >= 14) return 5;
    if (score >= 9) return 4;
    if (score >= 5) return 3;
    if (score >= 2) return 2;
    return 1;
  }

  bool _hasAny(String t, List<String> needles) {
    for (final n in needles) {
      if (t.contains(n)) return true;
    }
    return false;
  }

  List<String> _servicesFromText(String t) {
    final services = <String>{'ambulance'};
    if (_hasAny(t, const ['fire', 'smoke', 'burning', 'explosion'])) {
      services.add('fire_department');
    }
    if (_hasAny(t, const [
      'police',
      'hit and run',
      'drunk',
      'attack',
      'crime',
    ])) {
      services.add('police');
    }
    if (_hasAny(t, const ['trapped', 'pinned', 'rescue'])) {
      services.add('rescue');
    }
    if (_hasAny(t, const ['tow', 'towing', 'breakdown'])) {
      services.add('towing');
    }
    if (_hasAny(t, const ['puncture', 'flat tire', 'tyre', 'mechanic'])) {
      services.add('puncture_shop');
    }
    return services.toList();
  }

  String _firstAidQueryFromText(String t) {
    if (t.contains('bleed')) {
      return 'severe bleeding wound management tourniquet';
    }
    if (_hasAny(t, const ['burn', 'smoke'])) {
      return 'burn wound first aid cool water';
    }
    if (_hasAny(t, const ['not breathing', 'cpr', 'choking'])) {
      return 'CPR rescue breathing Heimlich';
    }
    if (_hasAny(t, const ['fracture', 'broken'])) {
      return 'fracture immobilization splint';
    }
    if (_hasAny(t, const ['head injury', 'concussion'])) {
      return 'head injury concussion protocol';
    }
    return 'general road accident first aid emergency response';
  }
}

class Tier2LocalTriage {
  final int severityLevel;
  final List<String> requiredServices;
  final String firstAidQuery;

  const Tier2LocalTriage({
    required this.severityLevel,
    required this.requiredServices,
    required this.firstAidQuery,
  });
}
