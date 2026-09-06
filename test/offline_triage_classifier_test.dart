import 'package:flutter_test/flutter_test.dart';
import 'package:roadsos/services/offline_triage_classifier.dart';

void main() {
  group('OfflineTriageClassifier', () {
    const classifier = OfflineTriageClassifier();

    group('Severity Estimation', () {
      test('level 5 keywords', () {
        expect(
          classifier
              .classify(transcript: 'He is dead', severityHint: 1)
              .severityLevel,
          5,
        );
        expect(
          classifier
              .classify(transcript: 'Fatal accident', severityHint: 1)
              .severityLevel,
          5,
        );
        expect(
          classifier
              .classify(transcript: 'not breathing', severityHint: 1)
              .severityLevel,
          5,
        );
        expect(
          classifier
              .classify(transcript: 'bleeding heavily', severityHint: 1)
              .severityLevel,
          5,
        );
        expect(
          classifier
              .classify(transcript: 'unconscious', severityHint: 1)
              .severityLevel,
          5,
        );
        expect(
          classifier
              .classify(transcript: 'he is trapped', severityHint: 1)
              .severityLevel,
          5,
        );
      });

      test('level 4 keywords', () {
        expect(
          classifier
              .classify(transcript: 'bleeding', severityHint: 1)
              .severityLevel,
          4,
        );
        expect(
          classifier
              .classify(transcript: 'broken leg', severityHint: 1)
              .severityLevel,
          4,
        );
        expect(
          classifier
              .classify(transcript: 'bone fracture', severityHint: 1)
              .severityLevel,
          4,
        );
      });

      test('level 3 keywords', () {
        expect(
          classifier
              .classify(transcript: 'I am hurt', severityHint: 1)
              .severityLevel,
          3,
        );
        expect(
          classifier
              .classify(transcript: 'feeling pain', severityHint: 1)
              .severityLevel,
          3,
        );
        expect(
          classifier
              .classify(transcript: 'car crash', severityHint: 1)
              .severityLevel,
          3,
        );
      });

      test('level 2 keywords', () {
        expect(
          classifier
              .classify(transcript: 'minor issue', severityHint: 1)
              .severityLevel,
          2,
        );
        expect(
          classifier
              .classify(transcript: 'just a scratch', severityHint: 1)
              .severityLevel,
          2,
        );
        expect(
          classifier
              .classify(transcript: 'a small bump', severityHint: 1)
              .severityLevel,
          2,
        );
      });

      test('default severity is 3', () {
        expect(
          classifier
              .classify(transcript: 'hello world', severityHint: 1)
              .severityLevel,
          3,
        );
      });
    });

    group('Severity Hint Merging', () {
      test('text severity > hint uses text severity', () {
        // text = 5 (dead), hint = 2 => 5
        expect(
          classifier
              .classify(transcript: 'dead', severityHint: 2)
              .severityLevel,
          5,
        );
      });

      test('text severity == hint uses text severity', () {
        // text = 4 (bleeding), hint = 4 => 4
        expect(
          classifier
              .classify(transcript: 'bleeding', severityHint: 4)
              .severityLevel,
          4,
        );
      });

      test('text severity < hint averages and rounds up', () {
        // text = 3 (hurt), hint = 5 => (3 + 5 + 1) ~/ 2 = 4
        expect(
          classifier
              .classify(transcript: 'hurt', severityHint: 5)
              .severityLevel,
          4,
        );

        // text = 2 (minor), hint = 5 => (2 + 5 + 1) ~/ 2 = 4
        expect(
          classifier
              .classify(transcript: 'minor', severityHint: 5)
              .severityLevel,
          4,
        );

        // text = 2 (minor), hint = 3 => (2 + 3 + 1) ~/ 2 = 3
        expect(
          classifier
              .classify(transcript: 'minor', severityHint: 3)
              .severityLevel,
          3,
        );
      });

      test('hint is clamped between 1 and 5', () {
        // text = 3 (hurt), hint = 10 => clamped to 5 => (3 + 5 + 1) ~/ 2 = 4
        expect(
          classifier
              .classify(transcript: 'hurt', severityHint: 10)
              .severityLevel,
          4,
        );

        // text = 5 (dead), hint = -10 => clamped to 1 => 5 > 1 ? 5 : ... => 5
        expect(
          classifier
              .classify(transcript: 'dead', severityHint: -10)
              .severityLevel,
          5,
        );
      });
    });

    group('Service Extraction', () {
      test('ambulance is always added', () {
        final result = classifier.classify(
          transcript: 'nothing',
          severityHint: 1,
        );
        expect(result.requiredServices, contains('ambulance'));
      });

      test('fire department', () {
        expect(
          classifier
              .classify(transcript: 'fire', severityHint: 1)
              .requiredServices,
          contains('fire_department'),
        );
        expect(
          classifier
              .classify(transcript: 'smoke', severityHint: 1)
              .requiredServices,
          contains('fire_department'),
        );
        expect(
          classifier
              .classify(transcript: 'burning', severityHint: 1)
              .requiredServices,
          contains('fire_department'),
        );
      });

      test('police', () {
        expect(
          classifier
              .classify(transcript: 'police', severityHint: 1)
              .requiredServices,
          contains('police'),
        );
        expect(
          classifier
              .classify(transcript: 'hit and run', severityHint: 1)
              .requiredServices,
          contains('police'),
        );
        expect(
          classifier
              .classify(transcript: 'drunk driver', severityHint: 1)
              .requiredServices,
          contains('police'),
        );
      });

      test('rescue', () {
        expect(
          classifier
              .classify(transcript: 'trapped inside', severityHint: 1)
              .requiredServices,
          contains('rescue'),
        );
        expect(
          classifier
              .classify(transcript: 'stuck', severityHint: 1)
              .requiredServices,
          contains('rescue'),
        );
        expect(
          classifier
              .classify(transcript: 'need rescue', severityHint: 1)
              .requiredServices,
          contains('rescue'),
        );
      });

      test('towing', () {
        expect(
          classifier
              .classify(transcript: 'need tow', severityHint: 1)
              .requiredServices,
          contains('towing'),
        );
        expect(
          classifier
              .classify(transcript: 'towing', severityHint: 1)
              .requiredServices,
          contains('towing'),
        );
      });

      test('puncture shop', () {
        expect(
          classifier
              .classify(transcript: 'puncture', severityHint: 1)
              .requiredServices,
          contains('puncture_shop'),
        );
        expect(
          classifier
              .classify(transcript: 'flat tire', severityHint: 1)
              .requiredServices,
          contains('puncture_shop'),
        );
        expect(
          classifier
              .classify(transcript: 'mechanic', severityHint: 1)
              .requiredServices,
          contains('puncture_shop'),
        );
      });

      test('showroom', () {
        expect(
          classifier
              .classify(transcript: 'repair', severityHint: 1)
              .requiredServices,
          contains('showroom'),
        );
        expect(
          classifier
              .classify(transcript: 'spare part', severityHint: 1)
              .requiredServices,
          contains('showroom'),
        );
        expect(
          classifier
              .classify(transcript: 'showroom', severityHint: 1)
              .requiredServices,
          contains('showroom'),
        );
      });

      test('multiple services', () {
        final result = classifier.classify(
          transcript: 'fire and police needed, flat tire',
          severityHint: 1,
        );
        expect(
          result.requiredServices,
          containsAll([
            'ambulance',
            'fire_department',
            'police',
            'puncture_shop',
          ]),
        );
      });
    });

    group('First Aid Query Builder', () {
      test('bleeding', () {
        expect(
          classifier
              .classify(transcript: 'bleed', severityHint: 1)
              .firstAidQuery,
          'severe bleeding wound management tourniquet',
        );
      });

      test('burn', () {
        expect(
          classifier
              .classify(transcript: 'burn', severityHint: 1)
              .firstAidQuery,
          'burn wound first aid cool water',
        );
      });

      test('breathing and choking', () {
        expect(
          classifier
              .classify(transcript: 'breath', severityHint: 1)
              .firstAidQuery,
          'CPR rescue breathing Heimlich',
        );
        expect(
          classifier
              .classify(transcript: 'chok', severityHint: 1)
              .firstAidQuery,
          'CPR rescue breathing Heimlich',
        );
      });

      test('fracture and broken', () {
        expect(
          classifier
              .classify(transcript: 'fracture', severityHint: 1)
              .firstAidQuery,
          'fracture immobilization splint',
        );
        expect(
          classifier
              .classify(transcript: 'broken', severityHint: 1)
              .firstAidQuery,
          'fracture immobilization splint',
        );
      });

      test('head and concussion', () {
        expect(
          classifier
              .classify(transcript: 'head', severityHint: 1)
              .firstAidQuery,
          'head injury concussion protocol',
        );
        expect(
          classifier
              .classify(transcript: 'concussion', severityHint: 1)
              .firstAidQuery,
          'head injury concussion protocol',
        );
      });

      test('default fallback', () {
        expect(
          classifier
              .classify(transcript: 'nothing specific', severityHint: 1)
              .firstAidQuery,
          'general road accident first aid emergency response',
        );
      });
    });
  });
}
