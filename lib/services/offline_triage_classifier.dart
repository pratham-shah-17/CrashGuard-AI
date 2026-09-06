/// Lightweight offline triage — deterministic keyword / sensor fusion only.
///
/// Intended footprint is tiny (rules only). A future ONNX/TFLite model can
/// replace [classify] while keeping the same API — **no on-device LLM/GGUF**.
/// Result of the offline tier (fits in <<50MB when backed by TFLite later).
class OfflineClassification {
  final int severityLevel;
  final List<String> requiredServices;
  final String firstAidQuery;

  const OfflineClassification({
    required this.severityLevel,
    required this.requiredServices,
    required this.firstAidQuery,
  });
}

/// Keyword + accelerometer hint classifier — safe on 3–4GB RAM devices.
class OfflineTriageClassifier {
  const OfflineTriageClassifier();

  OfflineClassification classify({
    required String transcript,
    required int severityHint,
  }) {
    // ⚡ Bolt Optimization: Only call toLowerCase() once and reuse the result.
    final lowerTranscript = transcript.toLowerCase();

    final severity = _mergeSeverity(
      _estimateSeverityFromText(lowerTranscript),
      severityHint,
    );
    final services = _extractServicesFromText(lowerTranscript);

    return OfflineClassification(
      severityLevel: severity,
      requiredServices: services,
      firstAidQuery: _buildFirstAidQuery(lowerTranscript),
    );
  }

  int _mergeSeverity(int fromText, int hint) {
    final h = hint.clamp(1, 5);
    return fromText > h
        ? fromText
        : fromText >= h
        ? fromText
        : ((fromText + h + 1) ~/ 2).clamp(1, 5);
  }

  int _estimateSeverityFromText(String lower) {
    if (lower.contains('dead') ||
        lower.contains('fatal') ||
        lower.contains('not breathing')) {
      return 5;
    }
    if (lower.contains('bleeding heavily') ||
        lower.contains('unconscious') ||
        lower.contains('trapped')) {
      return 5;
    }
    if (lower.contains('bleeding') ||
        lower.contains('broken') ||
        lower.contains('fracture')) {
      return 4;
    }
    if (lower.contains('hurt') ||
        lower.contains('pain') ||
        lower.contains('crash')) {
      return 3;
    }
    if (lower.contains('minor') ||
        lower.contains('scratch') ||
        lower.contains('bump')) {
      return 2;
    }
    return 3;
  }

  List<String> _extractServicesFromText(String lower) {
    final services = <String>{'ambulance'};
    if (lower.contains('fire') ||
        lower.contains('smoke') ||
        lower.contains('burning')) {
      services.add('fire_department');
    }
    if (lower.contains('police') ||
        lower.contains('hit and run') ||
        lower.contains('drunk')) {
      services.add('police');
    }
    if (lower.contains('trapped') ||
        lower.contains('stuck') ||
        lower.contains('rescue')) {
      services.add('rescue');
    }
    if (lower.contains('tow') || lower.contains('towing')) {
      services.add('towing');
    }
    if (lower.contains('puncture') ||
        lower.contains('flat tire') ||
        lower.contains('mechanic')) {
      services.add('puncture_shop');
    }
    if (lower.contains('repair') ||
        lower.contains('spare part') ||
        lower.contains('showroom')) {
      services.add('showroom');
    }
    return services.toList();
  }

  String _buildFirstAidQuery(String lower) {
    if (lower.contains('bleed')) {
      return 'severe bleeding wound management tourniquet';
    }
    if (lower.contains('burn')) {
      return 'burn wound first aid cool water';
    }
    if (lower.contains('breath') || lower.contains('chok')) {
      return 'CPR rescue breathing Heimlich';
    }
    if (lower.contains('fracture') || lower.contains('broken')) {
      return 'fracture immobilization splint';
    }
    if (lower.contains('head') || lower.contains('concussion')) {
      return 'head injury concussion protocol';
    }
    return 'general road accident first aid emergency response';
  }
}
