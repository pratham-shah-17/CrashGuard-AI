import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_log.dart';
import 'camera_triage_service.dart';
import 'connectivity_service.dart';
import 'first_aid_store.dart';
import 'gemma_local_service.dart';
import 'offline_triage_classifier.dart';
import 'tier2_local_triage_model.dart';

/// How triage was produced.
enum TriageSource {
  /// Cloud: Gemma 4 27B via Supabase Edge Function (highest quality)
  gemma4Cloud,

  /// Cloud + vision: Gemma 4 27B with crash-scene photo analyzed
  gemma4CloudVision,

  /// On-device: Gemma 4 E4B via flutter_gemma/LiteRT (offline-capable)
  gemma4OnDevice,

  /// Local weighted heuristic (offline, deterministic)
  localTier2,

  /// Keyword classifier (offline, always available, last resort)
  offlineClassifier,

  /// Web demo mode
  webDemo,
}

/// Model / pipeline state for UI.
enum ModelState { unloaded, ready, error, degraded }

/// Triage result from any tier in the Gemma 4 inference stack.
///
/// Phase 3 additions:
///   [confidence]       — 0.0–1.0 calibrated score based on source tier + signals.
///   [validationFlags]  — rule codes fired by [TriageValidationAgent].
///   [wasOverridden]    — true if any rule-based override changed the AI output.
///   [validationNotes]  — human-readable explanation of each override (shown in UI).
class TriageResult {
  final String functionCall;
  final String location;
  final int severityLevel;
  final List<String> requiredServices;
  final String firstAidQuery;
  final String compressedPayload;
  final String? thinkingTrace;
  final bool isDegradedMode;
  final TriageSource source;
  final bool visionUsed;

  // ── Phase 3: Zero-hallucination fields ───────────────────────────────────
  /// Calibrated confidence in this triage result (0.0 = none, 1.0 = certain).
  /// Computed by [TriageValidationAgent] after the producing tier completes.
  /// Tier baseline: Cloud=0.92, OnDevice=0.74, Heuristic=0.58, Classifier=0.42.
  final double confidence;

  /// Rule codes from [TriageValidationAgent] that fired on this result.
  /// Empty list means no overrides were needed.
  final List<String> validationFlags;

  /// True if [TriageValidationAgent] changed severity or services.
  final bool wasOverridden;

  /// Human-readable notes for each override — shown in [AiExplainabilityView].
  final List<String> validationNotes;

  const TriageResult({
    required this.functionCall,
    required this.location,
    required this.severityLevel,
    required this.requiredServices,
    required this.firstAidQuery,
    required this.compressedPayload,
    this.thinkingTrace,
    this.isDegradedMode = false,
    this.source = TriageSource.offlineClassifier,
    this.visionUsed = false,
    // Phase 3 fields — default to unvalidated state so existing call-sites compile.
    this.confidence = 0.70,
    this.validationFlags = const [],
    this.wasOverridden = false,
    this.validationNotes = const [],
  });

  Map<String, dynamic> toJson() => {
    'function_call': functionCall,
    'arguments': {
      'location': location,
      'severity_level': severityLevel,
      'required_services': requiredServices,
      'first_aid_rag_query': firstAidQuery,
      'compressed_payload': compressedPayload,
    },
    'thinking_trace': thinkingTrace,
    'degraded_mode': isDegradedMode,
    'source': source.name,
    'vision_used': visionUsed,
    'confidence': confidence,
    'validation_flags': validationFlags,
    'was_overridden': wasOverridden,
    'validation_notes': validationNotes,
  };

  String get sourceLabel {
    switch (source) {
      case TriageSource.gemma4Cloud:
        return 'Gemma 4 27B (cloud)';
      case TriageSource.gemma4CloudVision:
        return 'Gemma 4 27B + Vision (cloud)';
      case TriageSource.gemma4OnDevice:
        return 'Gemma 4 E4B (on-device)';
      case TriageSource.localTier2:
        return 'Local heuristic model';
      case TriageSource.offlineClassifier:
        return 'Offline keyword classifier';
      case TriageSource.webDemo:
        return 'Web demo';
    }
  }

  /// Human-readable confidence label for display.
  String get confidenceLabel {
    if (confidence >= 0.80) return 'High';
    if (confidence >= 0.60) return 'Moderate';
    return 'Low';
  }
}

/// AI Triage: 4-tier Gemma 4 inference stack with connectivity-aware routing.
///
/// Tier 1 (online):  Gemma 4 27B + vision via Supabase Edge Function
/// Tier 2 (offline): Gemma 4 E4B on-device via flutter_gemma/LiteRT
/// Tier 3 (offline): Weighted heuristic (Tier2LocalTriageModel)
/// Tier 4 (offline): Keyword classifier (OfflineTriageClassifier)
///
/// Connectivity-aware optimization:
/// When [ConnectivityService] reports [NetworkQuality.none], Tier 1 is skipped
/// immediately without waiting for the 5-second timeout. This saves up to 5s
/// of dispatch latency — critical since most Indian road crashes happen on
/// highways with intermittent or absent cellular coverage.
///
/// Vision: A bystander can capture a crash-scene photo via
/// [CameraTriageService.captureBystanderPhoto]. Gemma 4 27B is multimodal —
/// it analyzes the photo for fire, smoke, entrapment, and vehicle damage
/// alongside the audio transcript. This is a key Gemma-4-specific capability.
///
/// Phase 3: The [TriageValidationAgent] runs in the [EmergencyOrchestrator]
/// after this service returns, enforcing rule-based safety constraints before
/// dispatch. This service intentionally does not call the validation agent —
/// separation of concerns keeps triage and safety validation independent.
class AiTriageService {
  static const _classifier = OfflineTriageClassifier();
  static const _tier3 = Tier2LocalTriageModel();
  late final GemmaLocalService _gemmaLocal;
  late final ConnectivityService _connectivity;

  ModelState _state = ModelState.unloaded;
  String? _lastError;

  ModelState get state => _state;
  String? get lastError => _lastError;

  AiTriageService(this._gemmaLocal, this._connectivity);

  bool get _connectivityAwareTriage {
    final v = dotenv.env['CONNECTIVITY_AWARE_TRIAGE']?.trim().toLowerCase();
    return v == null || v.isEmpty || v == 'true' || v == '1';
  }

  Future<void> initializeModel() async {
    _state = ModelState.unloaded;
    if (kIsWeb) {
      _state = ModelState.degraded;
      _lastError = 'Web: triage uses offline tiers only.';
      return;
    }
    _state = ModelState.ready;
    _lastError = null;
    appLog.i(
      '[AiTriageService] Triage pipeline ready.\n'
      '  Tier 1: Gemma 4 27B + vision (Supabase Edge Function)\n'
      '  Tier 2: Gemma 4 E4B on-device (loading in background)\n'
      '  Tier 3: Weighted heuristic\n'
      '  Tier 4: Keyword classifier\n'
      '  Connectivity-aware: $_connectivityAwareTriage',
    );
    unawaited(_gemmaLocal.initialize());
  }

  Future<TriageResult> triageEmergency({
    required String audioTranscript,
    required String locationString,
    required int accelerometerSeverityHint,
    String languageCode = 'en',
    CapturedScenePhoto? scenePhoto,
  }) async {
    if (kIsWeb) {
      return _buildClassifierTriage(
        transcript: audioTranscript,
        location: locationString,
        severityHint: accelerometerSeverityHint,
        languageCode: languageCode,
      );
    }

    final skipCloud =
        _connectivityAwareTriage &&
        _connectivity.currentQuality == NetworkQuality.none;

    if (skipCloud) {
      appLog.d(
        '[Triage] Connectivity=none — skipping Tier 1 cloud (saves 5s timeout)',
      );
    } else {
      final cloudTimeout = _connectivity.currentQuality == NetworkQuality.wifi
          ? const Duration(seconds: 8)
          : const Duration(seconds: 5);
      try {
        final cloud = await _callGemma4Cloud(
          transcript: audioTranscript,
          location: locationString,
          severityHint: accelerometerSeverityHint,
          languageCode: languageCode,
          scenePhoto: scenePhoto,
        ).timeout(cloudTimeout);
        appLog.i('[Triage] Tier 1 — Gemma 4 27B cloud ✓ (text-only auto-SOS)');
        return cloud;
      } on Object catch (e, st) {
        appLog.d(
          '[Triage] Tier 1 unavailable, trying Tier 2 on-device',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (_gemmaLocal.isAvailable) {
      try {
        final onDevice = await _callGemma4OnDevice(
          transcript: audioTranscript,
          location: locationString,
          severityHint: accelerometerSeverityHint,
          languageCode: languageCode,
        ).timeout(const Duration(seconds: 8));
        if (onDevice != null) {
          appLog.i('[Triage] Tier 2 — Gemma 4 E4B on-device ✓');
          return onDevice;
        }
      } on Object catch (e, st) {
        appLog.d('[Triage] Tier 2 on-device failed', error: e, stackTrace: st);
      }
    }

    appLog.d('[Triage] Tier 3 — local heuristic model');
    return _buildTier3Triage(
      transcript: audioTranscript,
      location: locationString,
      severityHint: accelerometerSeverityHint,
      languageCode: languageCode,
    );
  }

  Future<TriageResult> performTriage({
    required dynamic location,
    required bool isBystander,
    String transcript = '',
    String languageCode = 'en',
    int severityHint = 3,
    CapturedScenePhoto? scenePhoto,
  }) async {
    final locationString = '${location.latitude},${location.longitude}';
    final ctx = transcript.trim().isEmpty
        ? (isBystander
              ? 'Bystander reporting roadside emergency'
              : 'Emergency SOS triggered')
        : transcript;

    return triageEmergency(
      audioTranscript: ctx,
      locationString: locationString,
      accelerometerSeverityHint: severityHint.clamp(1, 5),
      languageCode: languageCode,
      scenePhoto: scenePhoto,
    );
  }

  // ── Bystander vision path ────────────────────────────────────────────────

  Future<TriageResult> triageWithScenePhoto({
    required String audioTranscript,
    required String locationString,
    required int accelerometerSeverityHint,
    required CapturedScenePhoto scenePhoto,
    String languageCode = 'en',
  }) async {
    try {
      final cloud = await _callGemma4Cloud(
        transcript: audioTranscript,
        location: locationString,
        severityHint: accelerometerSeverityHint,
        languageCode: languageCode,
        scenePhoto: scenePhoto,
      ).timeout(const Duration(seconds: 8));
      appLog.i(
        '[Triage] Bystander vision triage ✓ '
        '(${scenePhoto.sizeKb} KB · source=${cloud.source.name})',
      );
      return cloud;
    } on Object catch (e, st) {
      appLog.d(
        '[Triage] Vision cloud failed — falling back to text-only triage',
        error: e,
        stackTrace: st,
      );
    }
    return triageEmergency(
      audioTranscript: audioTranscript,
      locationString: locationString,
      accelerometerSeverityHint: accelerometerSeverityHint,
      languageCode: languageCode,
    );
  }

  // ── Tier 1: Cloud Gemma 4 27B (+ optional vision) ─────────────────────────

  Future<TriageResult> _callGemma4Cloud({
    required String transcript,
    required String location,
    required int severityHint,
    required String languageCode,
    CapturedScenePhoto? scenePhoto,
  }) async {
    final client = Supabase.instance.client;
    final body = <String, dynamic>{
      'schema': 'roadsos.triage.v1',
      'transcript': transcript,
      'location': location,
      'severity_hint': severityHint,
      'language_code': languageCode,
    };

    if (scenePhoto != null) {
      body['image_base64'] = scenePhoto.base64Jpeg;
      body['image_type'] = 'image/jpeg';
    }

    final res = await client.functions.invoke('triage-gemini', body: body);

    final data = res.data;
    if (data is! Map) throw Exception('Edge triage returned non-object');
    final payload = Map<String, dynamic>.from(data);

    final severity =
        (payload['severity_level'] as num?)?.toInt().clamp(1, 5) ?? 4;
    final rawServices = payload['required_services'];
    final services = <String>{'ambulance'};
    if (rawServices is List) {
      for (final e in rawServices) {
        if (e is String && e.isNotEmpty) {
          final normalized = e.toLowerCase().replaceAll(' ', '_');
          if (_allowedServices.contains(normalized)) services.add(normalized);
        }
      }
    }

    final fromCloud = (payload['first_aid_focus'] as String?)?.trim();
    final fallbackQuery = _classifier
        .classify(transcript: transcript, severityHint: severityHint)
        .firstAidQuery;
    final aidQuery = (fromCloud != null && fromCloud.isNotEmpty)
        ? fromCloud
        : fallbackQuery;
    final thinking = payload['thinking_summary'] as String?;
    final modelUsed = payload['_model'] as String?;
    final visionUsed = payload['_vision_used'] == true;

    final verifiedAdvice = await FirstAidStore.getVerifiedAdvice(aidQuery);

    return TriageResult(
      functionCall: 'trigger_sos',
      location: location,
      severityLevel: severity,
      requiredServices: services.toList(),
      firstAidQuery: verifiedAdvice,
      compressedPayload: _buildCompressedPayload(
        location,
        severity,
        services.toList(),
      ),
      thinkingTrace: thinking != null
          ? '[${modelUsed ?? "Gemma 4 27B"}${visionUsed ? " + vision" : ""}] $thinking'
          : null,
      isDegradedMode: false,
      source: visionUsed
          ? TriageSource.gemma4CloudVision
          : TriageSource.gemma4Cloud,
      visionUsed: visionUsed,
    );
  }

  // ── Tier 2: On-device Gemma 4 E4B ────────────────────────────────────────

  Future<TriageResult?> _callGemma4OnDevice({
    required String transcript,
    required String location,
    required int severityHint,
    required String languageCode,
  }) async {
    final result = await _gemmaLocal.triageOffline(
      transcript: transcript,
      location: location,
      severityHint: severityHint,
      languageCode: languageCode,
    );
    if (result == null) return null;

    final severity =
        (result['severity_level'] as num?)?.toInt().clamp(1, 5) ?? 3;
    final rawServices = result['required_services'];
    final services = <String>{'ambulance'};
    if (rawServices is List) {
      for (final e in rawServices) {
        if (e is String && e.isNotEmpty) {
          // ⚡ Bolt Optimization: Pre-compute lowercase string
          // to eliminate redundant String allocations inside the loop.
          final normalized = e.toLowerCase();
          if (_allowedServices.contains(normalized)) {
            services.add(normalized);
          }
        }
      }
    }
    final aidQuery =
        (result['first_aid_focus'] as String?)?.trim() ??
        _classifier
            .classify(transcript: transcript, severityHint: severityHint)
            .firstAidQuery;
    final thinking = result['thinking_summary'] as String?;

    final verifiedAdvice = await FirstAidStore.getVerifiedAdvice(aidQuery);

    return TriageResult(
      functionCall: 'trigger_sos',
      location: location,
      severityLevel: severity,
      requiredServices: services.toList(),
      firstAidQuery: verifiedAdvice,
      compressedPayload: _buildCompressedPayload(
        location,
        severity,
        services.toList(),
      ),
      thinkingTrace: '[Gemma 4 E4B on-device] ${thinking ?? ""}',
      isDegradedMode: true,
      source: TriageSource.gemma4OnDevice,
    );
  }

  // ── Tier 3: Weighted heuristic ────────────────────────────────────────────

  Future<TriageResult> _buildTier3Triage({
    required String transcript,
    required String location,
    required int severityHint,
    required String languageCode,
  }) async {
    final c = _tier3.classify(
      transcript: transcript,
      severityHint: severityHint,
    );
    final verified = await FirstAidStore.getVerifiedAdvice(c.firstAidQuery);
    return TriageResult(
      functionCall: 'trigger_sos',
      location: location,
      severityLevel: c.severityLevel.clamp(1, 5),
      requiredServices: c.requiredServices,
      firstAidQuery: verified,
      compressedPayload: _buildCompressedPayload(
        location,
        c.severityLevel,
        c.requiredServices,
      ),
      thinkingTrace: languageCode == 'hi'
          ? 'स्थानीय भार-विश्लेषण मॉडल (Gemma 4 E4B उपलब्ध नहीं)।'
          : 'Local weighted heuristic (Gemma 4 E4B unavailable or loading).',
      isDegradedMode: true,
      source: TriageSource.localTier2,
    );
  }

  // ── Tier 4: Keyword classifier (always available, last resort) ────────────

  Future<TriageResult> _buildClassifierTriage({
    required String transcript,
    required String location,
    required int severityHint,
    required String languageCode,
  }) async {
    final c = _classifier.classify(
      transcript: transcript,
      severityHint: severityHint,
    );
    final severity = c.severityLevel;
    final services = c.requiredServices;
    final verified = await FirstAidStore.getVerifiedAdvice(c.firstAidQuery);

    return TriageResult(
      functionCall: 'trigger_sos',
      location: location,
      severityLevel: severity,
      requiredServices: services,
      firstAidQuery: verified,
      compressedPayload: _buildCompressedPayload(location, severity, services),
      thinkingTrace: languageCode == 'hi'
          ? 'ऑफ़लाइन कीवर्ड वर्गीकरण (Gemma 4 उपलब्ध नहीं)।'
          : 'Offline keyword classifier (Gemma 4 unavailable — no network).',
      isDegradedMode: true,
      source: TriageSource.offlineClassifier,
    );
  }

  static const Set<String> _allowedServices = {
    'ambulance',
    'police',
    'fire_department',
    'rescue',
    'towing',
    'puncture_shop',
    'showroom',
  };

  String _buildCompressedPayload(
    String location,
    int severity,
    List<String> services,
  ) {
    final svcCodes = services
        .map((s) {
          switch (s) {
            case 'ambulance':
              return 'AMB';
            case 'police':
              return 'POL';
            case 'fire_department':
              return 'FIR';
            case 'rescue':
              return 'RES';
            case 'towing':
              return 'TOW';
            case 'puncture_shop':
              return 'PUN';
            case 'showroom':
              return 'SHR';
            default:
              return 'UNK';
          }
        })
        .join(',');

    final loc = location.replaceAll(' ', '_');
    final clipped = loc.length <= 30 ? loc : loc.substring(0, 30);
    return 'LOC:$clipped|SEV:$severity|SVC:$svcCodes';
  }
}

final aiTriageServiceProvider = Provider<AiTriageService>((ref) {
  final gemmaLocal = ref.read(gemmaLocalServiceProvider);
  final connectivity = ref.read(connectivityServiceProvider);
  return AiTriageService(gemmaLocal, connectivity);
});
