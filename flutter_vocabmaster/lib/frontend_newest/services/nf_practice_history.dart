import 'package:flutter/foundation.dart';

/// Which of the last thirty days the learner practised on.
///
/// The week strip above it answers "have I done today's", which is a question
/// about now. This answers "am I actually keeping this up", which is the one
/// somebody asks in week three — and until now the app could not answer it at
/// all: seven days of history and then nothing, while the ledger on the device
/// held every day since the account was made.
///
/// A run of days is the only progress number here that a learner cannot argue
/// with. Level and XP go up because the app says so; words kept goes up
/// because they tapped Add. Turning up is the thing they did.
@immutable
class NfPracticeHistory {
  const NfPracticeHistory({
    required this.days,
    required this.activeDays,
    required this.longestRun,
  });

  /// Oldest first, ending with today. Length is always [window].
  final List<bool> days;

  /// How many of [days] were practised on.
  final int activeDays;

  /// The longest unbroken run inside the window.
  ///
  /// Not the streak: the streak is live and ends today, this is the best the
  /// learner has managed in a month. Someone who kept a nine-day run going and
  /// then missed yesterday has a streak of one and nothing to show for the
  /// nine, which is the moment people give up.
  final int longestRun;

  /// Thirty is a month at a glance and thirty cells still fit across a phone.
  static const int window = 30;

  /// [activeDayKeys] is `yyyy-MM-dd` for every day with practice; [today]
  /// anchors the window's last cell.
  static NfPracticeHistory from(Set<String> activeDayKeys, DateTime today) {
    final List<bool> days = <bool>[];
    for (int i = window - 1; i >= 0; i--) {
      final DateTime day = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      days.add(activeDayKeys.contains(keyFor(day)));
    }

    int active = 0;
    int run = 0;
    int longest = 0;
    for (final bool practised in days) {
      if (practised) {
        active++;
        run++;
        if (run > longest) {
          longest = run;
        }
      } else {
        run = 0;
      }
    }

    return NfPracticeHistory(
      days: List<bool>.unmodifiable(days),
      activeDays: active,
      longestRun: longest,
    );
  }

  /// The same key SQLite produces from `substr(createdAt, 1, 10)`.
  ///
  /// Built by hand rather than by slicing `toIso8601String()`, because that
  /// string is only zero-padded for the year: a date in a single-digit month
  /// still formats as `2026-09-06`, but relying on that is relying on a
  /// detail rather than on an agreement.
  static String keyFor(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Whether there is anything worth drawing.
  ///
  /// A brand-new account has one active day at most, and a strip of
  /// twenty-nine empty cells beside it reads as a month of failure rather than
  /// as a first day.
  bool get isWorthShowing => activeDays >= 3;
}
