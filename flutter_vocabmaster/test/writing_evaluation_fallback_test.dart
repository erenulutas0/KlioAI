import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/writing_practice_models.dart';

/// When the backend cannot evaluate a piece of writing it answers with a stand-in payload
/// carrying `score: 0` and `fallback: true`. The score there is the absence of a judgement,
/// not a judgement of zero — but the client never read the flag, so a transient AI failure
/// wrote a permanent zero into the learner's writing history and displayed it as
/// "your score out of 100".

void main() {
  test('the backend stand-in payload is recognised as a fallback', () {
    // Field-for-field as AiProxyService.buildWritingEvaluateFallback builds it.
    final evaluation = EvaluationData.fromJson({
      'score': 0,
      'strengths': <String>[],
      'improvements': ['AI degerlendirmesi gecici olarak olusturulamadi.'],
      'grammar': '',
      'vocabulary': '',
      'coherence': '',
      'overall': 'Lutfen yazinizi tekrar degerlendirin.',
      'contextRelevance': '',
      'fallback': true,
    });

    expect(evaluation.isFallback, isTrue,
        reason: 'a zero from a failed evaluation must never be stored as a real score');
  });

  test('a real evaluation is not treated as a fallback', () {
    final evaluation = EvaluationData.fromJson({
      'score': 75,
      'strengths': ['Uses specific examples'],
      'improvements': ['Vary sentence structure'],
      'grammar': 'Mostly correct',
      'vocabulary': 'Good range',
      'coherence': 'Clear',
      'overall': 'Great work',
      'contextRelevance': 'On topic',
    });

    expect(evaluation.isFallback, isFalse);
    expect(evaluation.score, 75);
  });

  test('a genuine zero from a real evaluation stays a real score', () {
    // An empty or off-topic submission can legitimately score 0. Only the fallback flag,
    // not the score, decides whether the result is trustworthy.
    final evaluation = EvaluationData.fromJson({
      'score': 0,
      'strengths': <String>[],
      'improvements': ['Write at least a few sentences'],
      'grammar': '',
      'vocabulary': '',
      'coherence': '',
      'overall': 'Nothing to evaluate',
      'contextRelevance': '',
      'fallback': false,
    });

    expect(evaluation.isFallback, isFalse);
    expect(evaluation.score, 0);
  });
}
