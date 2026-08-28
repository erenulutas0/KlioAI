import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/word_maturity.dart';

/// The app's answer to "how well does this learner know this word".
///
/// Two shipping screens have drawn these dots for as long as they have existed
/// and nothing has ever checked them. The reasoning behind them is careful —
/// they read the scheduler's INTERVAL rather than the review count, because the
/// backend increments the count on failures too and a word missed eight times
/// running would otherwise wear five dots. That reasoning is exactly the kind
/// that survives in a comment and quietly stops being true in the code.
///
/// The thresholds are the backend's own ladder: at the starting ease of 2.5,
/// SRSService produces 1, 6, 15, 38, 94 days, so a word recalled cleanly earns
/// one more dot per review. Those five numbers are the spine of this file.
void main() {
  Word word({
    int reviewCount = 0,
    double? easeFactor,
    DateTime? lastReview,
    DateTime? nextReview,
  }) =>
      Word(
        id: 1,
        englishWord: 'flight',
        turkishMeaning: 'uçuş',
        learnedDate: DateTime(2026, 1, 1),
        difficulty: 'easy',
        reviewCount: reviewCount,
        easeFactor: easeFactor,
        lastReviewDate: lastReview,
        nextReviewDate: nextReview,
      );

  /// A word the scheduler has graded, waiting [days] until its next review.
  Word waiting(int days, {int reviewCount = 3}) => word(
        reviewCount: reviewCount,
        lastReview: DateTime(2026, 3, 1),
        nextReview: DateTime(2026, 3, 1).add(Duration(days: days)),
      );

  group('the dots follow the scheduler', () {
    test('an ungraded word has none', () {
      expect(strengthDotsFor(word()), 0);
    });

    test('the backend ladder earns one dot per clean review', () {
      // 1, 6, 15, 38, 94 — the intervals SRSService actually produces at the
      // default ease. If the thresholds are ever rounded to something tidier,
      // these are the numbers that stop lining up.
      expect(strengthDotsFor(waiting(1)), 1);
      expect(strengthDotsFor(waiting(6)), 2);
      expect(strengthDotsFor(waiting(15)), 3);
      expect(strengthDotsFor(waiting(38)), 4);
      expect(strengthDotsFor(waiting(94)), 5);
    });

    test('each band holds its edges', () {
      expect(strengthDotsFor(waiting(5)), 1);
      expect(strengthDotsFor(waiting(13)), 2);
      expect(strengthDotsFor(waiting(14)), 3);
      expect(strengthDotsFor(waiting(29)), 3);
      expect(strengthDotsFor(waiting(30)), 4);
      expect(strengthDotsFor(waiting(59)), 4);
      expect(strengthDotsFor(waiting(60)), 5);
    });

    test('a lapse takes the dots back down', () {
      // The whole reason the dots read the interval. A failed grade drops the
      // wait to a single day and leaves the review count untouched, so a word
      // reviewed nine times and missed the last time is a one-dot word.
      expect(strengthDotsFor(waiting(1, reviewCount: 9)), 1);
    });

    test('a high review count alone earns nothing', () {
      // reviewCount is incremented on failures too. On its own it is not
      // evidence of anything, and this is the case that would betray a version
      // that had quietly gone back to counting reviews.
      final Word missedRepeatedly = word(
        reviewCount: 8,
        easeFactor: 1.3,
        lastReview: DateTime(2026, 3, 1),
        nextReview: DateTime(2026, 3, 2),
      );
      expect(strengthDotsFor(missedRepeatedly), 1);
    });
  });

  group('when the dates are missing', () {
    test('the scheduler formula stands in', () {
      // Rows from older local-database versions carry a count and an ease but
      // no dates. Replaying SM-2 over them is an upper bound, and an estimate
      // beats an empty row on a list where every other word shows progress.
      expect(strengthDotsFor(word(reviewCount: 1)), 1);
      expect(strengthDotsFor(word(reviewCount: 2)), 2);
      expect(strengthDotsFor(word(reviewCount: 3, easeFactor: 2.5)), 3);
    });

    test('a floor-ease word climbs slowly, as it should', () {
      // 6 * 1.3^2 = 10 days: still two dots after four reviews, which is the
      // truth about a word that keeps being scraped through.
      expect(strengthDotsFor(word(reviewCount: 4, easeFactor: 1.3)), 2);
    });

    test('a corrupt count cannot crash the list', () {
      // 6 * 2.5^998 overflows a double, and .round() throws on infinity. This
      // is one row in a scrolling list; throwing here takes the screen down.
      expect(strengthDotsFor(word(reviewCount: 1000, easeFactor: 2.5)), 5);
    });

    test('a nonsense ease is treated as the default', () {
      expect(strengthDotsFor(word(reviewCount: 3, easeFactor: double.nan)), 3);
    });
  });

  group('a backwards schedule is not evidence', () {
    test('a next review before the last one falls back to the formula', () {
      // Clock changes and bad payloads both produce this. A negative interval
      // must not read as a zero-day one.
      final Word backwards = word(
        reviewCount: 3,
        easeFactor: 2.5,
        lastReview: DateTime(2026, 3, 10),
        nextReview: DateTime(2026, 3, 1),
      );
      expect(strengthDotsFor(backwards), 3);
    });
  });

  group('the three stages agree with the dots', () {
    test('never graded is fresh', () {
      expect(maturityFor(word()), WordMaturity.fresh);
    });

    test('inside a fortnight is still learning', () {
      expect(maturityFor(waiting(1)), WordMaturity.learning);
      expect(maturityFor(waiting(13)), WordMaturity.learning);
    });

    test('a fortnight or more is known', () {
      expect(maturityFor(waiting(14)), WordMaturity.known);
      expect(maturityFor(waiting(94)), WordMaturity.known);
    });

    test('nothing is known that does not show three dots', () {
      // The point of deriving one from the other. A summary saying "12 known"
      // beside rows showing two dots would be the app disagreeing with itself,
      // which it already does on three screens.
      for (final int days in <int>[0, 1, 5, 6, 13, 14, 29, 30, 59, 60, 400]) {
        final Word w = waiting(days);
        final bool known = maturityFor(w) == WordMaturity.known;
        expect(known, strengthDotsFor(w) >= 3, reason: '$days days');
      }
    });
  });

  group('counting a deck', () {
    test('adds up to the deck', () {
      final MaturityCounts counts = MaturityCounts.of(<Word>[
        word(),
        word(),
        waiting(3),
        waiting(20),
        waiting(90),
      ]);
      expect(counts.fresh, 2);
      expect(counts.learning, 1);
      expect(counts.known, 2);
      expect(counts.total, 5);
    });

    test('an empty deck counts to nothing rather than to null', () {
      final MaturityCounts counts = MaturityCounts.of(const <Word>[]);
      expect(counts.total, 0);
      expect(counts.known, 0);
    });
  });
}
