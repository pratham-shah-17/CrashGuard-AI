import 'package:flutter_test/flutter_test.dart';
import 'package:roadsos/services/ai_triage_service.dart';
import 'package:roadsos/services/driving_mode_service.dart';
import 'package:roadsos/services/triage_validation_agent.dart';

TriageResult _base({
  required int severity,
  List<String> services = const ['police'],
  TriageSource source = TriageSource.gemma4Cloud,
}) {
  return TriageResult(
    functionCall: 'dispatch_emergency',
    location: '12.97,77.59',
    severityLevel: severity,
    requiredServices: services,
    firstAidQuery: 'bleeding',
    compressedPayload: 'payload',
    source: source,
  );
}

void main() {
  group('TriageValidationAgent', () {
    test('driving mode raises severity below 3 to 3 and ensures ambulance', () {
      final raw = _base(severity: 2, services: ['police']);
      final r = triageValidationAgent.validate(
        raw: raw,
        drivingMode: DrivingMode.driving,
        gyroPeakRadPerSec: 0,
        accelSeverityHint: 2,
      );
      expect(r.triage.severityLevel, 3);
      expect(r.triage.requiredServices, contains('ambulance'));
      expect(r.flags, contains('severity_floor_driving_mode'));
    });

    test('high gyro peak raises severity to at least 4', () {
      final raw = _base(severity: 3, services: ['ambulance']);
      final r = triageValidationAgent.validate(
        raw: raw,
        drivingMode: DrivingMode.stationary,
        gyroPeakRadPerSec: 4.2,
        accelSeverityHint: 2,
      );
      expect(r.triage.severityLevel, greaterThanOrEqualTo(4));
      expect(r.flags, contains('severity_raised_by_gyro_crash'));
    });

    test('accelerometer hint floor raises low AI severity', () {
      final raw = _base(severity: 2, services: ['ambulance']);
      final r = triageValidationAgent.validate(
        raw: raw,
        drivingMode: DrivingMode.stationary,
        gyroPeakRadPerSec: 0,
        accelSeverityHint: 5,
      );
      expect(r.triage.severityLevel, greaterThanOrEqualTo(4));
      expect(r.flags, contains('severity_raised_by_sensor'));
    });

    test('severity >= 3 forces ambulance when missing', () {
      final raw = _base(severity: 4, services: ['fire_department']);
      final r = triageValidationAgent.validate(
        raw: raw,
        drivingMode: DrivingMode.stationary,
        gyroPeakRadPerSec: 0,
        accelSeverityHint: 2,
      );
      expect(r.triage.requiredServices, contains('ambulance'));
      expect(r.flags, contains('ambulance_added'));
    });

    test('empty services list gets ambulance', () {
      final raw = _base(severity: 1, services: []);
      final r = triageValidationAgent.validate(
        raw: raw,
        drivingMode: DrivingMode.stationary,
        gyroPeakRadPerSec: 0,
        accelSeverityHint: 1,
      );
      expect(r.triage.requiredServices, contains('ambulance'));
      expect(r.flags, contains('ambulance_added'));
    });

    test('documents overrides when rules fire', () {
      final raw = _base(severity: 2, services: ['police']);
      final r = triageValidationAgent.validate(
        raw: raw,
        drivingMode: DrivingMode.driving,
        gyroPeakRadPerSec: 0,
        accelSeverityHint: 2,
      );
      expect(r.wasOverridden, isTrue);
      expect(r.overrideNotes, isNotEmpty);
      expect(r.triage.wasOverridden, isTrue);
    });
  });
}
