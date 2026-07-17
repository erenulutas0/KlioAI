import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/pronunciation_report_service.dart';

void main() {
  final service = PronunciationReportService();

  group('Substitution evidence (expected vs heard)', () {
    test('unclear mark carries what Whisper actually heard', () {
      final report = service.evaluate(
        targetText: 'The ship sails today',
        transcript: 'The sheep sails today',
        durationMs: 2000,
      );

      final unclear = report.targetWordMarks
          .firstWhere((m) => m.status == PronunciationWordStatus.unclear);
      expect(unclear.word, 'ship');
      expect(unclear.heardAs, 'sheep');
      expect(report.nextStep, contains("Expected 'ship' but heard 'sheep'"));
    });

    test('matched words carry no heardAs', () {
      final report = service.evaluate(
        targetText: 'Good morning',
        transcript: 'Good morning',
        durationMs: 1000,
      );
      for (final mark in report.targetWordMarks) {
        expect(mark.status, PronunciationWordStatus.matched);
        expect(mark.heardAs, isNull);
      }
    });
  });

  group('Tokenizer normalization (no false errors)', () {
    test('digits and words converge: "2" equals "two"', () {
      final report = service.evaluate(
        targetText: 'I have two cats',
        transcript: 'I have 2 cats',
        durationMs: 1500,
      );
      expect(report.accuracyScore, 100,
          reason: 'Digit spelling difference is not a pronunciation error');
      expect(report.missingWords, isEmpty);
    });

    test('contractions converge: "don\'t" equals "do not"', () {
      final report = service.evaluate(
        targetText: "Don't stop now",
        transcript: 'Do not stop now',
        durationMs: 1500,
      );
      expect(report.accuracyScore, 100,
          reason: 'Contraction expansion is not a pronunciation error');
      expect(report.missingWords, isEmpty);
    });

    test("possessive 's is deliberately NOT expanded", () {
      final report = service.evaluate(
        targetText: "The cat's hat",
        transcript: 'The cats hat',
        durationMs: 1200,
      );
      // Apostrophe stripped on both sides: cats == cats, full match.
      expect(report.accuracyScore, 100);
    });
  });
}
