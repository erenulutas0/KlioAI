import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/services/nf_practice_history.dart';

/// Thirty days of turning up, from a ledger that has held them all along.
///
/// The app showed seven days and then nothing, so the question people actually
/// ask in week three — am I keeping this up — had no answer on any screen.
/// These pin the two ways that answer could lie: a window that drifts off the
/// day it claims to end on, and a strip drawn for somebody who has no month
/// yet.
void main() {
  DateTime day(int y, int m, int d) => DateTime(y, m, d);
  String key(int y, int m, int d) => NfPracticeHistory.keyFor(day(y, m, d));

  test('the window is thirty days and ends today', () {
    final NfPracticeHistory history =
        NfPracticeHistory.from(<String>{}, day(2026, 9, 6));

    expect(history.days, hasLength(30));
    expect(history.days.last, isFalse);
    expect(history.activeDays, 0);
    expect(history.longestRun, 0);
  });

  test('today lands in the last cell, not the first', () {
    // Drawn oldest-first, so a reversed window would show today thirty days
    // ago and every recent day as empty.
    final NfPracticeHistory history = NfPracticeHistory.from(
      <String>{key(2026, 9, 6)},
      day(2026, 9, 6),
    );

    expect(history.days.last, isTrue);
    expect(history.days.first, isFalse);
    expect(history.activeDays, 1);
  });

  test('the oldest cell is twenty-nine days back, inclusive', () {
    final NfPracticeHistory history = NfPracticeHistory.from(
      <String>{key(2026, 8, 8), key(2026, 8, 7)},
      day(2026, 9, 6),
    );

    // 8 August is exactly 29 days before 6 September and belongs in the strip;
    // 7 August is one day further and does not.
    expect(history.days.first, isTrue);
    expect(history.activeDays, 1);
  });

  test('the window crosses a month boundary correctly', () {
    // Naive arithmetic on the day-of-month is how a strip ends up claiming
    // 31 August was 1 September.
    final NfPracticeHistory history = NfPracticeHistory.from(
      <String>{key(2026, 8, 31), key(2026, 9, 1)},
      day(2026, 9, 3),
    );

    expect(history.activeDays, 2);
    // Two consecutive calendar days across the boundary are one run.
    expect(history.longestRun, 2);
  });

  test('the longest run is the best in the window, not the live streak', () {
    // Nine days kept and then yesterday missed: the streak is what it is, and
    // the nine still happened. Showing only the streak is the moment people
    // decide the month was wasted.
    final Set<String> nineThenAGap = <String>{
      for (int i = 3; i <= 11; i++) key(2026, 9, i),
    };

    final NfPracticeHistory history =
        NfPracticeHistory.from(nineThenAGap, day(2026, 9, 13));

    expect(history.activeDays, 9);
    expect(history.longestRun, 9);
    expect(history.days.last, isFalse, reason: 'today has not happened yet');
  });

  test('two separate runs report the longer one', () {
    final Set<String> days = <String>{
      key(2026, 9, 1), key(2026, 9, 2),
      key(2026, 9, 5), key(2026, 9, 6), key(2026, 9, 7), key(2026, 9, 8),
    };

    final NfPracticeHistory history =
        NfPracticeHistory.from(days, day(2026, 9, 10));

    expect(history.activeDays, 6);
    expect(history.longestRun, 4);
  });

  test('a new account is not shown a month of failure', () {
    // One or two days in, twenty-eight empty cells say "you have missed
    // almost every day" to somebody who has not had the chance.
    for (int active = 0; active <= 2; active++) {
      final Set<String> days = <String>{
        for (int i = 0; i < active; i++)
          NfPracticeHistory.keyFor(
              day(2026, 9, 6).subtract(Duration(days: i))),
      };
      expect(NfPracticeHistory.from(days, day(2026, 9, 6)).isWorthShowing,
          isFalse,
          reason: '$active active days should stay hidden');
    }

    final Set<String> three = <String>{
      key(2026, 9, 6), key(2026, 9, 5), key(2026, 9, 4),
    };
    expect(NfPracticeHistory.from(three, day(2026, 9, 6)).isWorthShowing,
        isTrue);
  });

  test('the day key matches what SQLite produces', () {
    // The set comes from `substr(createdAt, 1, 10)` over an ISO-8601 column.
    // A key built any other way silently matches nothing and draws an empty
    // month for an active learner.
    expect(NfPracticeHistory.keyFor(day(2026, 9, 6)), '2026-09-06');
    expect(NfPracticeHistory.keyFor(day(2026, 12, 25)), '2026-12-25');
    expect(NfPracticeHistory.keyFor(DateTime(2026, 1, 1, 23, 59)), '2026-01-01');
    expect(
      NfPracticeHistory.keyFor(day(2026, 9, 6)),
      DateTime(2026, 9, 6).toIso8601String().substring(0, 10),
    );
  });

  test('a day outside the window is ignored rather than counted', () {
    final NfPracticeHistory history = NfPracticeHistory.from(
      <String>{key(2026, 1, 1), key(2026, 9, 6)},
      day(2026, 9, 6),
    );

    expect(history.activeDays, 1);
  });
}
