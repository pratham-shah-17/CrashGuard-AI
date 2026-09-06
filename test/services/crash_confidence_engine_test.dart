import 'package:flutter_test/flutter_test.dart';
import 'package:roadsos/services/crash_confidence_engine.dart';

void main() {
  group('CrashConfidenceEngine.score', () {
    test('returns LOW tier for minor signals', () {
      final signals = CrashSignals(
        accelPeakMs2: 12.0, // 10% of 120 -> 0.1 * 0.30 = 0.03
        gyroPeakRadPerSec: 0.8, // 10% of 8 -> 0.1 * 0.22 = 0.022
        speedBeforeKmh: 12.0, // 10% of 120 -> 0.1 * 0.20 = 0.02
        speedDropKmh: 12.0, // 10% of 120 -> 0.1 * 0.15 = 0.015
        bluetoothVehicleDisconnect: false,
        postImpactDeviceStill: false,
      );

      final result = CrashConfidenceEngine.score(signals);

      expect(result.tier, equals(CrashConfidenceTier.low));
      expect(result.incidentLabel, equals('Possible incident detected'));
      expect(result.score, closeTo(0.087, 0.001));

      expect(result.breakdown['accel'], closeTo(0.03, 0.001));
      expect(result.breakdown['gyro'], closeTo(0.022, 0.001));
      expect(result.breakdown['speed'], closeTo(0.02, 0.001));
      expect(result.breakdown['drop'], closeTo(0.015, 0.001));
      expect(result.breakdown['bt'], equals(0.0));
      expect(result.breakdown['still'], equals(0.0));
    });

    test('returns MEDIUM tier for moderate signals', () {
      final signals = CrashSignals(
        accelPeakMs2: 60.0, // 50% of 120 -> 0.5 * 0.30 = 0.15
        gyroPeakRadPerSec: 4.0, // 50% of 8 -> 0.5 * 0.22 = 0.11
        speedBeforeKmh: 60.0, // 50% of 120 -> 0.5 * 0.20 = 0.10
        speedDropKmh: 60.0, // 50% of 120 -> 0.5 * 0.15 = 0.075
        bluetoothVehicleDisconnect: false,
        postImpactDeviceStill: false,
      );

      final result = CrashConfidenceEngine.score(signals);

      expect(result.tier, equals(CrashConfidenceTier.medium));
      expect(result.incidentLabel, equals('Possible incident detected'));
      expect(result.score, closeTo(0.435, 0.001));
    });

    test('returns HIGH tier for severe signals', () {
      final signals = CrashSignals(
        accelPeakMs2: 120.0,
        gyroPeakRadPerSec: 8.0,
        speedBeforeKmh: 120.0,
        speedDropKmh: 120.0,
        bluetoothVehicleDisconnect: true,
        postImpactDeviceStill: true,
      );

      final result = CrashConfidenceEngine.score(signals);

      expect(result.tier, equals(CrashConfidenceTier.high));
      expect(
        result.incidentLabel,
        equals('Detected incident — possible emergency'),
      );
      expect(result.score, equals(1.0));
    });

    test('clamps negative values to 0.0', () {
      final signals = CrashSignals(
        accelPeakMs2: -10.0,
        gyroPeakRadPerSec: -1.0,
        speedBeforeKmh: -20.0,
        speedDropKmh: -5.0,
        bluetoothVehicleDisconnect: false,
        postImpactDeviceStill: false,
      );

      final result = CrashConfidenceEngine.score(signals);

      expect(result.score, equals(0.0));
      expect(result.breakdown['accel'], equals(0.0));
      expect(result.breakdown['gyro'], equals(0.0));
      expect(result.breakdown['speed'], equals(0.0));
      expect(result.breakdown['drop'], equals(0.0));
    });

    test('clamps values exceeding maxima to 1.0 equivalent', () {
      final signals = CrashSignals(
        accelPeakMs2: 200.0, // max 120.0
        gyroPeakRadPerSec: 20.0, // max 8.0
        speedBeforeKmh: 200.0, // max 120.0
        speedDropKmh: 200.0, // max 120.0
        bluetoothVehicleDisconnect: true,
        postImpactDeviceStill: true,
      );

      final result = CrashConfidenceEngine.score(signals);

      expect(result.score, equals(1.0));
      expect(result.tier, equals(CrashConfidenceTier.high));
      expect(result.breakdown['accel'], closeTo(0.30, 0.001));
      expect(result.breakdown['gyro'], closeTo(0.22, 0.001));
      expect(result.breakdown['speed'], closeTo(0.20, 0.001));
      expect(result.breakdown['drop'], closeTo(0.15, 0.001));
    });
  });
}
