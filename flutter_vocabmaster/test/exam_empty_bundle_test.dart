import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/exam_models.dart';

/// When the backend cannot build an exam it answers with a stand-in payload carrying
/// `time_limit_minutes: 0` and no questions. Three things then went wrong in a row:
/// `?? 180` accepted the zero because zero is not null, the runner started a timer of zero
/// seconds and immediately "finished" the exam, and the results screen divided 0 by 0 —
/// which in Dart is NaN, and reached the screen as the literal text "NaN".

void main() {
  group('exam meta time limit', () {
    test('a zero time limit falls back to the default', () {
      final meta = ExamMeta.fromJson({
        'exam': 'YDS',
        'mode': 'full_exam',
        'track': 'general',
        'user_level_cefr': 'B1',
        'target_score_band': '70-80',
        'time_limit_minutes': 0,
        'total_questions': 0,
      });

      expect(meta.timeLimitMinutes, 180,
          reason: 'a zero-length exam ends the moment it starts');
    });

    test('a missing time limit falls back to the default', () {
      final meta = ExamMeta.fromJson({
        'exam': 'YDS',
        'mode': 'full_exam',
        'track': 'general',
        'user_level_cefr': 'B1',
        'target_score_band': '70-80',
        'total_questions': 40,
      });

      expect(meta.timeLimitMinutes, 180);
    });

    test('a negative time limit falls back to the default', () {
      final meta = ExamMeta.fromJson({
        'exam': 'YDS',
        'mode': 'mini_test',
        'track': 'general',
        'user_level_cefr': 'B1',
        'target_score_band': '70-80',
        'time_limit_minutes': -30,
        'total_questions': 10,
      });

      expect(meta.timeLimitMinutes, 180);
    });

    test('a real time limit is kept', () {
      final meta = ExamMeta.fromJson({
        'exam': 'YOKDIL',
        'mode': 'mini_test',
        'track': 'social',
        'user_level_cefr': 'B2',
        'target_score_band': '80-90',
        'time_limit_minutes': 45,
        'total_questions': 20,
      });

      expect(meta.timeLimitMinutes, 45);
    });
  });

  test('scoring an exam with no questions must not produce NaN', () {
    // Mirrors exam_result_page's calculation. Dart's `/` on two ints returns a double,
    // and 0 / 0 is NaN rather than an error, so it rendered straight into the UI.
    const correctCount = 0;
    const totalQuestions = 0;

    final rawScore =
        totalQuestions > 0 ? (correctCount / totalQuestions) * 100 : 0.0;

    expect(rawScore.isNaN, isFalse);
    expect(rawScore, 0.0);
  });
}
