import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';
import 'ai_triage_service.dart';
import 'gemma_local_service.dart';
import 'india_emergency_routing.dart';
import 'location_service.dart';
import 'user_profile_service.dart';
import 'vital_signs_service.dart';

/// Hard cap for the SMS body — 1 standard SMS segment is 160 GSM-7 chars.
/// We aim well below this (≈150) so carrier headers / encoding shifts do not
/// silently fragment the message and lose ordering on Indian operators.
const int kMaxStructured112SmsLength = 155;

/// Builds a structured, dispatcher-friendly emergency SMS body for 112 ERSS /
/// 108 / 100 / 101 in India. Uses on-device Gemma 4 E4B when available to
/// compress vitals + profile + state route into a single-segment SMS, with a
/// deterministic template fallback that NEVER fails — life-safety path must
/// always produce a valid payload even when the model is missing.
///
/// Why a dedicated service vs. embedding in [EmergencyOrchestrator]:
///   1. Single responsibility (rulebook Phase 2 services rule).
///   2. Lets the bystander coach + family circle reuse the same compressor.
///   3. Easy to unit-test (deterministic template branch).
class StructuredSmsService {
  StructuredSmsService(this._ref);

  final Ref _ref;

  /// Build a single-segment SMS body following the RSOS pipe schema.
  ///
  /// Schema (≈150 chars):
  ///   `RSOS|{state}|{lat},{lng}|S{sev}|{svc}|{vitals}|{profile}|inc:{id8}`
  ///
  /// Field rules:
  ///   - state    → ISO 3166-2 code (e.g. IN-KA) from [resolveIndiaEmergencyRoute]
  ///   - lat/lng  → 4dp (≈11 m precision, enough for 112 dispatch + fits SMS)
  ///   - sev      → S1..S5
  ///   - svc      → comma-joined trim ('amb,pol,fire')
  ///   - vitals   → 'C?|B?|Bl?' (conscious / breathing / bleeding, '?' = unknown)
  ///   - profile  → 'A32 B+ Aller:None' or '?'
  ///   - id8      → first 8 chars of incident UUID
  Future<String> buildStructured112Sms({
    required String incidentId,
    required LocationFix location,
    required TriageResult triage,
    UserProfile? profileOverride,
    bool useGemma = true,
  }) async {
    final route = resolveIndiaEmergencyRoute(
      location.latitude,
      location.longitude,
    );
    final stateCode = route?.stateCode ?? 'IN';
    final UserProfile profile =
        profileOverride ?? _ref.read(userProfileProvider);
    final idShort = incidentId
        .replaceAll('-', '')
        .padRight(8, '0')
        .substring(0, 8);

    final servicesShort = _shortServices(triage.requiredServices);
    final profileShort = _shortProfile(profile);
    final vitals = _vitalsFromProvider();

    final deterministic = _buildDeterministic(
      stateCode: stateCode,
      lat: location.latitude,
      lng: location.longitude,
      severity: triage.severityLevel,
      servicesShort: servicesShort,
      vitals: vitals,
      profileShort: profileShort,
      idShort: idShort,
    );

    final gemmaText = useGemma
        ? await _tryGemmaCompose(
            stateCode: stateCode,
            stateName: route?.stateName ?? 'Unknown',
            lat: location.latitude,
            lng: location.longitude,
            severity: triage.severityLevel,
            services: triage.requiredServices,
            profile: profile,
            idShort: idShort,
            vitals: vitals,
            deterministicFallback: deterministic,
          )
        : null;

    final chosen = gemmaText ?? deterministic;
    final trimmed = _truncateGsm7Safe(chosen, kMaxStructured112SmsLength);
    appLog.d(
      '[StructuredSMS] built ${trimmed.length}-char SMS '
      '(gemma=${gemmaText != null}, state=$stateCode, sev=${triage.severityLevel})',
    );
    return trimmed;
  }

  // ── Internals ────────────────────────────────────────────────────────────

  String _buildDeterministic({
    required String stateCode,
    required double lat,
    required double lng,
    required int severity,
    required String servicesShort,
    required String vitals,
    required String profileShort,
    required String idShort,
  }) {
    final latS = lat.toStringAsFixed(4);
    final lngS = lng.toStringAsFixed(4);
    return 'RSOS|$stateCode|$latS,$lngS|S$severity|$servicesShort|$vitals|$profileShort|inc:$idShort';
  }

  String _shortServices(List<String> services) {
    if (services.isEmpty) return 'amb';
    const map = {
      'ambulance': 'amb',
      'police': 'pol',
      'fire_department': 'fire',
      'rescue': 'rsq',
      'towing': 'tow',
    };
    final out = <String>[];
    for (final s in services) {
      final v = map[s] ?? s.substring(0, s.length.clamp(0, 3));
      if (!out.contains(v)) out.add(v);
      if (out.length >= 3) break;
    }
    return out.join(',');
  }

  String _shortProfile(UserProfile p) {
    final bt = p.bloodType.trim();
    final hasBt = bt.isNotEmpty && bt.toLowerCase() != 'unknown';
    final allergies = p.allergies.trim();

    // ⚡ Bolt Optimization: Lazy evaluation of toLowerCase()
    // By only evaluating allergiesLower if allergies is not empty, we avoid allocating a new string for empty inputs.
    // Reusing the variable saves a redundant toLowerCase() allocation compared to checking 'none' and 'n/a' individually.
    final allergiesLower = allergies.isNotEmpty ? allergies.toLowerCase() : '';
    final hasAllergy =
        allergies.isNotEmpty &&
        allergiesLower != 'none' &&
        allergiesLower != 'n/a';

    if (!hasBt && !hasAllergy) return '?';

    final allergyShort = hasAllergy
        ? allergies.length > 12
              ? allergies.substring(0, 12)
              : allergies
        : 'None';
    final btShort = hasBt ? bt : '?';
    return 'B$btShort A:$allergyShort';
  }

  /// Pulls the most recent bystander-entered vitals from [vitalSignsProvider]
  /// and renders them into the 'C?|B?|Bl?' SMS slot.
  ///
  /// Notation (single SMS segment friendly):
  ///   Hxxx  — heart rate bpm (e.g. H120)
  ///   Rxx   — respiratory rate per minute (e.g. R28)
  ///   O88   — SpO2 % (e.g. O88 = 88% oxygen — critical)
  ///   '?'   — unknown / not entered (fallback so dispatcher knows to probe)
  String _vitalsFromProvider() {
    try {
      final v = _ref.read(vitalSignsProvider);
      if (v == null) return 'C?B?Bl?';
      final parts = <String>[
        'H${v.bpm}',
        'R${v.respiratoryRate}',
        'O${v.bloodOxygen.round()}',
      ];
      return parts.join(',');
    } on Object catch (_) {
      return 'C?B?Bl?';
    }
  }

  String _truncateGsm7Safe(String input, int maxLen) {
    final cleaned = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= maxLen) return cleaned;
    return cleaned.substring(0, maxLen);
  }

  Future<String?> _tryGemmaCompose({
    required String stateCode,
    required String stateName,
    required double lat,
    required double lng,
    required int severity,
    required List<String> services,
    required UserProfile profile,
    required String idShort,
    required String vitals,
    required String deterministicFallback,
  }) async {
    try {
      final gemma = _ref.read(gemmaLocalServiceProvider);
      if (!gemma.isAvailable) return null;

      final prompt =
          'You compress road-accident reports into a single 112 SMS for India dispatchers.\n'
          'Rules:\n'
          '- Output ONE line of plain text, max 150 GSM-7 characters.\n'
          '- No markdown, no quotes, no explanation.\n'
          '- Use this exact pipe schema:\n'
          '  RSOS|<state>|<lat>,<lng>|S<sev>|<svc>|<vitals>|<profile>|inc:<id>\n'
          '- svc: comma-joined short codes (amb,pol,fire,rsq,tow).\n'
          '- profile: "B<blood> A:<allergy>" or "?".\n'
          '- vitals: keep "C?B?Bl?" when unknown.\n\n'
          'Inputs:\n'
          '  state_code: $stateCode\n'
          '  state_name: $stateName\n'
          '  lat: ${lat.toStringAsFixed(4)}\n'
          '  lng: ${lng.toStringAsFixed(4)}\n'
          '  severity: $severity\n'
          '  services_needed: ${services.join(',')}\n'
          '  blood_type: ${profile.bloodType}\n'
          '  allergies: ${profile.allergies}\n'
          '  conditions: ${profile.conditions}\n'
          '  incident_id: $idShort\n'
          '  vitals_known: $vitals\n\n'
          'Fallback (use if unsure): $deterministicFallback';

      final raw = await gemma.generate(prompt);
      if (raw == null) return null;
      final line = raw
          .trim()
          .split('\n')
          .firstWhere((l) => l.contains('RSOS|'), orElse: () => '');
      if (line.isEmpty) return null;
      return line.trim();
    } on Object catch (e, st) {
      appLog.d('[StructuredSMS] gemma compose skipped: $e', stackTrace: st);
      return null;
    }
  }
}

final structuredSmsServiceProvider = Provider<StructuredSmsService>((ref) {
  return StructuredSmsService(ref);
});
