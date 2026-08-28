import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/models/nf_plan_state.dart';
import 'package:vocabmaster/models/word.dart';

/// The first screen's arithmetic, which had never been checked.
///
/// Every case here is a way of being wrong that a learner would notice and the
/// app would not: a check mark on a step that is not finished, or three
/// unfinished steps on a day that is. The Today page carried all of this inside
/// a factory that read nine fields off a provider, so none of it could be
/// asked a question without building most of the app first.
void main() {
  final DateTime now = DateTime(2026, 8, 28, 14, 30);

  Word word({DateTime? due}) => Word(
        id: due?.microsecondsSinceEpoch ?? 0,
        englishWord: 'word${due?.day ?? 0}',
        turkishMeaning: 'kelime',
        learnedDate: DateTime(2026, 1, 1),
        difficulty: 'easy',
        nextReviewDate: due,
      );

  NfPlanState plan({
    List<Word>? words,
    int dailyGoal = 5,
    int learnedToday = 0,
    int ownSentenceCount = 0,
    int translationsToday = 0,
  }) =>
      NfPlanState.from(
        words: words ?? <Word>[],
        dailyGoal: dailyGoal,
        learnedToday: learnedToday,
        ownSentenceCount: ownSentenceCount,
        translationsToday: translationsToday,
        now: now,
      );

  group('review', () {
    test('a word due earlier today is due', () {
      // The end of the day, not the moment: a word scheduled for 09:00 is still
      // this morning's work at 14:30, and one scheduled for 23:00 is today's.
      final NfPlanState state = plan(words: <Word>[
        word(due: DateTime(2026, 8, 28, 9)),
        word(due: DateTime(2026, 8, 28, 23, 59)),
      ]);
      expect(state.reviewTarget, 2);
      expect(state.reviewDone, isFalse);
    });

    test('a word due tomorrow is not', () {
      final NfPlanState state =
          plan(words: <Word>[word(due: DateTime(2026, 8, 29))]);
      expect(state.reviewTarget, 0);
      expect(state.reviewDone, isTrue);
    });

    test('an overdue word is still due', () {
      final NfPlanState state =
          plan(words: <Word>[word(due: DateTime(2026, 7, 1))]);
      expect(state.reviewTarget, 1);
      expect(state.reviewDone, isFalse);
    });

    test('a deck nothing has scheduled is not a finished deck', () {
      // The case worth being careful about. Every word unscheduled means the
      // schedule has not started, not that the learner is caught up -- and a
      // green check on a fresh deck says "nothing to do here" to the person
      // with the most to do.
      final NfPlanState state =
          plan(words: <Word>[word(), word(), word()]);
      expect(state.reviewDone, isFalse);
      expect(state.reviewTarget, 3);
    });

    test('an unscheduled deck asks for a batch, not for all of it', () {
      final NfPlanState state = plan(
        words: List<Word>.generate(40, (_) => word()),
      );
      expect(state.reviewTarget, NfPlanState.unscheduledReviewTarget);
    });

    test('one scheduled word is enough for the schedule to be real', () {
      // Mixed decks follow the schedule: the scheduled words are the ones the
      // review flow can act on, so the count is theirs.
      final NfPlanState state = plan(words: <Word>[
        word(),
        word(),
        word(due: DateTime(2026, 8, 29)),
      ]);
      expect(state.reviewTarget, 0);
      expect(state.reviewDone, isTrue);
    });

    test('an empty deck has nothing to review and says so', () {
      final NfPlanState state = plan();
      expect(state.hasWords, isFalse);
      expect(state.reviewTarget, 0);
      expect(state.reviewDone, isFalse);
    });
  });

  group('new words', () {
    test('the goal is the learner\'s own number', () {
      expect(plan(dailyGoal: 20).newTarget, 20);
    });

    test('a missing goal falls back rather than reading as finished', () {
      // A stored zero would otherwise make learnDone true at zero words learned
      // and put a check mark on an untouched day.
      final NfPlanState state = plan(dailyGoal: 0);
      expect(state.newTarget, NfPlanState.defaultDailyGoal);
      expect(state.learnDone, isFalse);
    });

    test('reaching the goal finishes the step', () {
      expect(plan(dailyGoal: 5, learnedToday: 5).learnDone, isTrue);
    });

    test('passing the goal does not unfinish it', () {
      expect(plan(dailyGoal: 5, learnedToday: 9).learnDone, isTrue);
    });

    test('one short is not done', () {
      expect(plan(dailyGoal: 5, learnedToday: 4).learnDone, isFalse);
    });
  });

  group('translation', () {
    test('the set is capped at its size', () {
      expect(plan(ownSentenceCount: 40).translationTarget,
          NfPlanState.translationSetSize);
    });

    test('fewer sentences than a full set is a smaller set', () {
      expect(plan(ownSentenceCount: 2).translationTarget, 2);
    });

    test('no sentences means the step cannot be complete', () {
      // Nothing to translate is not the same as having translated everything.
      final NfPlanState state = plan(ownSentenceCount: 0, translationsToday: 9);
      expect(state.translationTarget, 0);
      expect(state.translationDone, isFalse);
    });

    test('enough translations finish the step', () {
      expect(plan(ownSentenceCount: 3, translationsToday: 3).translationDone,
          isTrue);
    });
  });

  group('the day as a whole', () {
    test('nothing done counts as nothing done', () {
      expect(plan(words: <Word>[word()]).stepsDone, 0);
    });

    test('the counter counts every finished step', () {
      final NfPlanState state = plan(
        words: <Word>[word(due: DateTime(2026, 8, 29))],
        dailyGoal: 5,
        learnedToday: 5,
        ownSentenceCount: 3,
        translationsToday: 3,
      );
      expect(state.stepsDone, NfPlanState.stepCount);
      expect(state.allDone, isTrue);
    });

    test('a partly finished day is partly finished', () {
      final NfPlanState state = plan(
        words: <Word>[word(due: DateTime(2026, 8, 29))],
        dailyGoal: 5,
        learnedToday: 5,
      );
      expect(state.stepsDone, 2);
      expect(state.allDone, isFalse);
    });
  });
}
