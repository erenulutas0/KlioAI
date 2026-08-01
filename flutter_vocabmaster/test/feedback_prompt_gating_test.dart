import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/feedback_prompt_service.dart';
import 'package:vocabmaster/services/in_app_review_service.dart';

/// The store rating prompt used to fire on the third completed practice, unconditionally,
/// at a learner nobody had asked anything — about an app that for three months was serving
/// hardcoded template sentences as though a model had written them.
///
/// With almost no users and no reviews yet, one star is a large and permanent fraction of
/// the rating. So the private question comes first, and only an answer that says the app is
/// working opens the door to the store.
///
/// These tests pin the gate. The other half of the point is not being a pest: an answer
/// closes the question, and a dismissal closes it for good.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final prompt = FeedbackPromptService();
  final review = InAppReviewService();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('when the question is asked', () {
    test('not before the learner has done enough to have an opinion', () async {
      expect(await prompt.shouldAsk(0), isFalse);
      expect(await prompt.shouldAsk(2), isFalse);
    });

    test('on the third completed practice', () async {
      expect(await prompt.shouldAsk(3), isTrue);
    });

    test('a happy answer ends it — they have been sent to the store already', () async {
      await prompt.recordAnswer(FeedbackPromptService.answerGood, 3);

      expect(await prompt.shouldAsk(4), isFalse);
      expect(await prompt.shouldAsk(400), isFalse);
    });

    test('an unhappy answer is revisited once, much later', () async {
      // Their complaint was about a build that will not exist by then, so asking again is
      // a different question rather than the same one repeated.
      await prompt.recordAnswer(FeedbackPromptService.answerBad, 3);

      expect(await prompt.shouldAsk(4), isFalse);
      expect(await prompt.shouldAsk(10), isFalse);
      expect(await prompt.shouldAsk(15), isTrue);
    });

    test('"do not ask" means never, not later', () async {
      await prompt.recordDismissed();

      expect(await prompt.shouldAsk(3), isFalse);
      expect(await prompt.shouldAsk(500), isFalse);
    });
  });

  group('the store rating gate', () {
    test('counting a practice does not by itself earn a rating request', () async {
      // This is the whole change: recordPracticeCompletion used to call requestReview().
      expect(await review.recordPracticeCompletion(), 1);
      expect(await review.recordPracticeCompletion(), 2);
      expect(await review.isEligibleForStorePrompt(), isFalse);
    });

    test('eligibility needs the same three completions the question does', () async {
      await review.recordPracticeCompletion();
      await review.recordPracticeCompletion();
      await review.recordPracticeCompletion();

      expect(await review.isEligibleForStorePrompt(), isTrue);
    });

    test('once asked, never asked again', () async {
      SharedPreferences.setMockInitialValues({
        'in_app_review:practice_completion_count': 30,
        'in_app_review:requested': true,
      });

      expect(await review.isEligibleForStorePrompt(), isFalse);
    });
  });

  test('both features count the same practices', () async {
    // They read one key on purpose. Two counters would drift, and a learner would end up
    // asked twice for one session.
    await review.recordPracticeCompletion();
    await review.recordPracticeCompletion();
    await review.recordPracticeCompletion();

    expect(await prompt.completions(), 3);
    expect(await prompt.shouldAsk(await prompt.completions()), isTrue);
  });
}
