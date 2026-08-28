import 'dart:math' as math;

import 'word.dart';

/// The lowest ease the scheduler will go to. Mirrors `MIN_EASE_FACTOR` in the
/// backend's `SRSService`; used only to sanitise values read back from storage.
const double _kMinEase = 1.3;

/// The ease a word starts at, per `SRSService.initializeWordForSRS`.
const double _kDefaultEase = 2.5;

/// The fixed second-review interval, per `SRSService.SECOND_INTERVAL`.
const int _kSecondInterval = 6;

/// How far a word has travelled, as three stages rather than five dots.
///
/// The dots are for a row in a list, where five steps read as progress. Three
/// stages are for counting: how much of this deck is new, how much is in hand,
/// how much has stuck. Both are read off the same number so they cannot
/// disagree — the app already carries three different opinions about word
/// strength on three different screens, and a fourth would be worse than none.
enum WordMaturity {
  /// Never graded. The scheduler has no opinion about it yet.
  fresh,

  /// Graded, but the scheduler still wants it back inside a fortnight.
  learning,

  /// The scheduler is willing to wait two weeks or more.
  known,
}

/// Which stage [word] is at.
///
/// Derived from [strengthDotsFor] rather than from its own thresholds, so the
/// dots on a row and the count in a summary are always the same claim: nothing
/// is `known` that does not also show three dots.
WordMaturity maturityFor(Word word) {
  final int dots = strengthDotsFor(word);
  if (dots <= 0) {
    return WordMaturity.fresh;
  }
  if (dots <= 2) {
    return WordMaturity.learning;
  }
  return WordMaturity.known;
}

/// How many of the five dots a word has earned.
///
/// The dots report the SM-2 **interval** — how many days the scheduler is
/// currently willing to wait before asking again — because that is the only
/// number in the model that actually means "this one sticks".
///
/// `reviewCount` is the obvious candidate and is the wrong one: the backend
/// (`SRSService.submitReview`) increments it on every grade, failures included,
/// and a failed grade (quality < 3) drops the interval back to a single day
/// without touching the count. A word missed eight times running would wear
/// five dots. The interval cannot lie that way — it *is* the scheduler's
/// confidence, expressed in days.
///
/// The thresholds are the backend's own ladder rather than round numbers. With
/// the starting ease of 2.5 its formula (1, 6, then 6 × ease^(n−2)) produces
/// 1, 6, 15, 38, 94 days, so a word recalled cleanly gains exactly one dot per
/// review, and a word scraping along at the 1.3 ease floor climbs far more
/// slowly — which is the truth about it:
///
///   0 dots  never graded
///   1 dot   under 6 days   — first review, or knocked back to 1 by a lapse
///   2 dots  6–13 days      — the fixed second-review step, and where a
///                            low-ease word stalls for several reviews
///   3 dots  14–29 days
///   4 dots  30–59 days
///   5 dots  60 days or more
int strengthDotsFor(Word word) {
  final int? interval = _scheduledIntervalDays(word);
  if (interval == null) {
    return 0;
  }
  if (interval < _kSecondInterval) {
    return 1;
  }
  if (interval < 14) {
    return 2;
  }
  if (interval < 30) {
    return 3;
  }
  if (interval < 60) {
    return 4;
  }
  return 5;
}

/// The gap the scheduler last chose, in days, or null if it has never chosen
/// one for this word.
int? _scheduledIntervalDays(Word word) {
  if (word.reviewCount <= 0) {
    return null;
  }

  final DateTime? last = word.lastReviewDate;
  final DateTime? next = word.nextReviewDate;
  if (last != null && next != null) {
    final int days = _startOfDay(next).difference(_startOfDay(last)).inDays;
    if (days >= 0) {
      return days;
    }
  }

  // Rows that predate both dates being stored — older local-database versions,
  // or a word rebuilt from a partial payload — can still be placed by replaying
  // the scheduler's own formula over the count and ease we do have. It assumes
  // the last grade was a pass, so it reads as an upper bound; better a stated
  // estimate than an empty row where every other word shows progress.
  return _sm2Interval(word.reviewCount, word.easeFactor);
}

/// `SRSService.calculateInterval` for a passing grade.
int _sm2Interval(int reviewCount, double? easeFactor) {
  if (reviewCount <= 1) {
    return 1;
  }
  if (reviewCount == 2) {
    return _kSecondInterval;
  }

  final double ease = (easeFactor == null || !easeFactor.isFinite)
      ? _kDefaultEase
      : easeFactor.clamp(_kMinEase, 5.0);

  final num raw = _kSecondInterval * math.pow(ease, reviewCount - 2);
  // A corrupt review count can push this past double range, and `.round()`
  // throws on infinity. Anything this large is mastered by any measure.
  if (!raw.isFinite || raw > 36500) {
    return 36500;
  }
  return raw.round();
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// How many words sit at each stage.
///
/// A record rather than a map so a caller cannot ask for a stage that does not
/// exist, and cannot get null for one nobody has reached yet.
class MaturityCounts {
  const MaturityCounts({
    required this.fresh,
    required this.learning,
    required this.known,
  });

  factory MaturityCounts.of(Iterable<Word> words) {
    int fresh = 0;
    int learning = 0;
    int known = 0;
    for (final Word word in words) {
      switch (maturityFor(word)) {
        case WordMaturity.fresh:
          fresh++;
        case WordMaturity.learning:
          learning++;
        case WordMaturity.known:
          known++;
      }
    }
    return MaturityCounts(fresh: fresh, learning: learning, known: known);
  }

  final int fresh;
  final int learning;
  final int known;

  int get total => fresh + learning + known;
}
