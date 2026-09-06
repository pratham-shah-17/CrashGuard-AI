import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roadsos/services/ai_triage_service.dart';
import 'package:roadsos/services/location_service.dart';
import 'package:roadsos/services/structured_sms_service.dart';
import 'package:roadsos/services/user_profile_service.dart';

/// Deterministic tests for the 112 SMS schema. Gemma-4 path is bypassed
/// (`useGemma: false`) so the template fallback alone is exercised — that's
/// the only branch the test runner can reach without a downloaded model.
void main() {
  late ProviderContainer container;
  late StructuredSmsService svc;

  setUp(() {
    container = ProviderContainer();
    svc = container.read(structuredSmsServiceProvider);
  });

  tearDown(() => container.dispose());

  test('Bengaluru high-severity SOS produces compliant SMS', () async {
    final body = await svc.buildStructured112Sms(
      incidentId: '01234567-89ab-cdef-0123-456789abcdef',
      location: LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracy: 8,
        source: 'gps',
        timestamp: DateTime.now(),
      ),
      triage: TriageResult(
        functionCall: 'dispatch_emergency',
        location: '12.9716,77.5946',
        severityLevel: 5,
        requiredServices: const ['ambulance', 'police'],
        firstAidQuery: 'severe bleeding',
        compressedPayload: 'LAT:12.97160|LNG:77.59460|ACC:8m|SRC:gps',
        thinkingTrace: null,
        isDegradedMode: false,
        source: TriageSource.localTier2,
        visionUsed: false,
      ),
      profileOverride: UserProfile(
        fullName: 'Asha Rao',
        bloodType: 'B+',
        allergies: 'Penicillin',
        medications: 'None',
        conditions: 'None',
        emergencyContact: '+919876543210',
      ),
      useGemma: false,
    );

    expect(body.length, lessThanOrEqualTo(kMaxStructured112SmsLength));
    expect(body, startsWith('RSOS|IN-KA|'));
    expect(body, contains('|S5|'));
    expect(body, contains('amb,pol'));
    expect(body, contains('B+'));
    expect(body, contains('Penicillin'));
    expect(body, contains('inc:0123456'));
  });

  test(
    'Chennai medium severity routes to Tamil Nadu with "?" profile',
    () async {
      final body = await svc.buildStructured112Sms(
        incidentId: 'abcdefab-0000-0000-0000-000000000000',
        location: LocationFix(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracy: 12,
          source: 'gps',
          timestamp: DateTime.now(),
        ),
        triage: TriageResult(
          functionCall: 'dispatch_emergency',
          location: '13.0827,80.2707',
          severityLevel: 3,
          requiredServices: const ['ambulance'],
          firstAidQuery: 'general',
          compressedPayload: 'x',
          thinkingTrace: null,
          isDegradedMode: false,
          source: TriageSource.localTier2,
          visionUsed: false,
        ),
        profileOverride: UserProfile(),
        useGemma: false,
      );

      expect(body, startsWith('RSOS|IN-TN|'));
      expect(body, contains('|S3|'));
      expect(body, contains('|amb|'));
      expect(body, contains('|?|'));
      expect(body.length, lessThanOrEqualTo(kMaxStructured112SmsLength));
    },
  );

  test('Off-India coordinates fall back to "IN" state token', () async {
    final body = await svc.buildStructured112Sms(
      incidentId: '11111111-aaaa-bbbb-cccc-dddddddddddd',
      location: LocationFix(
        latitude: 40.7128,
        longitude: -74.0060,
        accuracy: 20,
        source: 'gps',
        timestamp: DateTime.now(),
      ),
      triage: TriageResult(
        functionCall: 'dispatch_emergency',
        location: '40.7128,-74.0060',
        severityLevel: 4,
        requiredServices: const ['ambulance', 'police', 'fire_department'],
        firstAidQuery: 'general',
        compressedPayload: 'x',
        thinkingTrace: null,
        isDegradedMode: false,
        source: TriageSource.localTier2,
        visionUsed: false,
      ),
      profileOverride: UserProfile(),
      useGemma: false,
    );

    expect(body, startsWith('RSOS|IN|'));
    expect(body, contains('amb,pol,fire'));
    expect(body.length, lessThanOrEqualTo(kMaxStructured112SmsLength));
  });
}
