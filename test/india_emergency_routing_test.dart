import 'package:flutter_test/flutter_test.dart';
import 'package:roadsos/services/india_emergency_routing.dart';

void main() {
  group('resolveIndiaEmergencyRoute', () {
    group('coarse boxes exact bounds', () {
      test('Karnataka box bounds (11.5–18.6N, 74.0–78.9E)', () {
        // SW corner
        var r = resolveIndiaEmergencyRoute(11.5, 74.0);
        expect(r?.stateCode, 'IN-KA');

        // NW corner
        r = resolveIndiaEmergencyRoute(18.6, 74.0);
        expect(r?.stateCode, 'IN-KA');

        // NE corner
        r = resolveIndiaEmergencyRoute(18.6, 78.9);
        expect(r?.stateCode, 'IN-KA');

        // SE corner
        r = resolveIndiaEmergencyRoute(11.5, 78.9);
        expect(r?.stateCode, 'IN-KA');
      });

      test(
        'Tamil Nadu box bounds (8.0–13.6N, 76.0–80.6E) excluding KA overlap',
        () {
          // TN SW corner
          var r = resolveIndiaEmergencyRoute(8.0, 76.0);
          expect(r?.stateCode, 'IN-TN');

          // TN NW corner (Note: 13.6, 76.0 overlaps with KA box. The code checks KA first,
          // so it will resolve to IN-KA. We test a point just east of KA box for TN NW corner.)
          r = resolveIndiaEmergencyRoute(13.6, 79.0);
          expect(r?.stateCode, 'IN-TN');

          // TN NE corner
          r = resolveIndiaEmergencyRoute(13.6, 80.6);
          expect(r?.stateCode, 'IN-TN');

          // TN SE corner
          r = resolveIndiaEmergencyRoute(8.0, 80.6);
          expect(r?.stateCode, 'IN-TN');
        },
      );

      test(
        'Tamil Nadu bounds that overlap with Karnataka resolve to Karnataka',
        () {
          // The point (12.0, 77.0) is in both TN box (8.0-13.6, 76.0-80.6)
          // and KA box (11.5-18.6, 74.0-78.9).
          // Since KA is checked first in _resolveByCoarseBoxes, it must resolve to KA.
          final r = resolveIndiaEmergencyRoute(12.0, 77.0);
          expect(r?.stateCode, 'IN-KA');
        },
      );
    });

    group('just outside coarse boxes', () {
      test('Just outside Karnataka box', () {
        // KA Box: 11.5–18.6N, 74.0–78.9E

        // Just south (11.4, 75.0) -> outside KA box, falls through.
        final rSouth = resolveIndiaEmergencyRoute(11.4, 75.0);
        expect(rSouth?.stateCode, isNot('IN-KA'));

        // Just north (18.7, 75.0) -> outside KA box.
        final rNorth = resolveIndiaEmergencyRoute(18.7, 75.0);
        expect(rNorth?.stateCode, isNot('IN-KA'));

        // Just west (15.0, 73.9) -> outside KA box.
        final rWest = resolveIndiaEmergencyRoute(15.0, 73.9);
        expect(rWest?.stateCode, isNot('IN-KA'));
      });

      test('Just outside Tamil Nadu box', () {
        // TN Box: 8.0–13.6N, 76.0–80.6E

        // Just south (7.9, 78.0) -> outside TN box, outside KA box.
        final rSouth = resolveIndiaEmergencyRoute(7.9, 78.0);
        expect(rSouth?.stateCode, isNotNull);
        expect(rSouth?.stateCode, isNot('IN-TN'));

        // Just east (10.0, 80.7) -> outside TN box
        final rEast = resolveIndiaEmergencyRoute(10.0, 80.7);
        expect(rEast?.stateCode, isNotNull);
        expect(rEast?.stateCode, isNot('IN-TN'));
      });
    });

    test('Bengaluru resolves to Karnataka (coarse box)', () {
      final r = resolveIndiaEmergencyRoute(12.9716, 77.5946);
      expect(r, isNotNull);
      expect(r!.stateCode, 'IN-KA');
      expect(r.ambulanceNumber, '108');
      expect(r.nationalNumber, '112');
    });

    test('Chennai resolves to Tamil Nadu (coarse box)', () {
      final r = resolveIndiaEmergencyRoute(13.0827, 80.2707);
      expect(r, isNotNull);
      expect(r!.stateCode, 'IN-TN');
      expect(r.ambulanceNumber, '108');
      expect(r.nationalNumber, '112');
    });

    test('Delhi resolves via centroid (outside coarse boxes)', () {
      final r = resolveIndiaEmergencyRoute(28.6139, 77.2090);
      expect(r, isNotNull);
      expect(r!.stateCode, 'IN-DL');
      expect(r.ambulanceNumber, '108');
      expect(r.nationalNumber, '112');
    });

    test('outside India returns null', () {
      expect(resolveIndiaEmergencyRoute(40.7, -74.0), isNull);
    });
  });
}
