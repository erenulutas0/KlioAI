import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/pronunciation_report_service.dart';

void main() {
  group('PronunciationReportService', () {
    final service = PronunciationReportService();

    test('returns a high score for close transcript match', () {
      final report = service.evaluate(
        targetText: 'Learning a language becomes easier with practice.',
        transcript: 'Learning a language becomes easier with practice',
        durationMs: 3500,
      );

      expect(report.accuracyScore, 100);
      expect(report.overallScore, greaterThanOrEqualTo(85));
      expect(report.missingWords, isEmpty);
      expect(report.extraWords, isEmpty);
      expect(
        report.targetWordMarks.every(
          (mark) => mark.status == PronunciationWordStatus.matched,
        ),
        isTrue,
      );
    });

    test('reports missing words from the target text', () {
      final report = service.evaluate(
        targetText: 'The speaker gave a short example.',
        transcript: 'The speaker gave example',
        durationMs: 2500,
      );

      expect(report.missingWords, containsAll(['a', 'short']));
      expect(report.accuracyScore, lessThan(100));
      expect(
        report.targetWordMarks
            .where((mark) => mark.status == PronunciationWordStatus.missing)
            .map((mark) => mark.word),
        containsAll(['a', 'short']),
      );
      expect(report.nextStep, contains('a, short'));
    });

    test('reports extra words from the transcript', () {
      final report = service.evaluate(
        targetText: 'I need to explain the problem.',
        transcript: 'I need to really explain the big problem',
        durationMs: 3500,
      );

      expect(report.extraWords, containsAll(['really', 'big']));
      expect(report.overallScore, lessThan(100));
    });

    test('marks substituted words as unclear in the target review', () {
      final report = service.evaluate(
        targetText: 'The article explains the problem.',
        transcript: 'The article explains a problem',
        durationMs: 3000,
      );

      expect(report.missingWords, contains('the'));
      expect(report.extraWords, contains('a'));
      expect(
        report.targetWordMarks
            .where((mark) => mark.status == PronunciationWordStatus.unclear)
            .map((mark) => mark.word),
        contains('the'),
      );
    });
  });
}
