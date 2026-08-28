import 'dart:math' as math;

import 'package:flutter/material.dart' show DateUtils;

import '../../models/word.dart';

/// What today's plan is asking for, and how much of it is done.
///
/// Pulled out of the Today page because it decides something a learner can be
/// wrong about in a way that matters: a check mark on a step they have not
/// finished, or an unfinished-looking day after they finished it. The page it
/// came from reads nine different things off a provider, which is why none of
/// this had ever been tested — the arithmetic was unreachable without building
/// most of the app around it.
///
/// It takes plain values so a test can hand it a deck and a day and ask what
/// the plan says.
class NfPlanState {
  const NfPlanState({
    required this.hasWords,
    required this.reviewTarget,
    required this.reviewDone,
    required this.newTarget,
    required this.learnedToday,
    required this.learnDone,
    required this.translationTarget,
    required this.translationDone,
  });

  /// The daily goal used when the learner has never set one.
  static const int defaultDailyGoal = 5;

  /// How many sentences one translation set holds.
  static const int translationSetSize = 5;

  /// What "review" means for a deck no schedule has touched yet.
  static const int unscheduledReviewTarget = 10;

  /// How many of the three steps there are. Named rather than written as 3
  /// wherever a fraction is shown.
  static const int stepCount = 3;

  final bool hasWords;

  final int reviewTarget;
  final bool reviewDone;

  final int newTarget;
  final int learnedToday;
  final bool learnDone;

  final int translationTarget;
  final bool translationDone;

  /// Steps finished, for the counter on the card.
  int get stepsDone =>
      (reviewDone ? 1 : 0) + (learnDone ? 1 : 0) + (translationDone ? 1 : 0);

  bool get allDone => reviewDone && learnDone && translationDone;

  /// Reads the plan off a deck and a day.
  ///
  /// [words] is everything the learner has saved, [dailyGoal] their configured
  /// number of new words, [learnedToday] how many they have added today,
  /// [ownSentenceCount] how many sentences hang off their own words, and
  /// [translationsToday] how many translation exercises they have been paid XP
  /// for. [now] is injected so a test does not depend on the clock.
  factory NfPlanState.from({
    required List<Word> words,
    required int dailyGoal,
    required int learnedToday,
    required int ownSentenceCount,
    required int translationsToday,
    required DateTime now,
  }) {
    // A word counts as due once its scheduled date has arrived. Anything with
    // no schedule cannot be judged, so a deck with no schedule at all falls
    // back to a fixed batch rather than announcing the learner is caught up.
    final DateTime endOfToday = DateUtils.dateOnly(now)
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    int scheduled = 0;
    int due = 0;
    for (final Word word in words) {
      final DateTime? next = word.nextReviewDate;
      if (next == null) {
        continue;
      }
      scheduled++;
      if (!next.isAfter(endOfToday)) {
        due++;
      }
    }
    final bool hasSchedule = scheduled > 0;

    // The goal is the learner's configured number, never the size of the
    // generated daily-words set: the provider celebrates at exactly this
    // number, and any other figure here would put a check on the plan while
    // the app still considered the day unfinished.
    final int newTarget = dailyGoal > 0 ? dailyGoal : defaultDailyGoal;

    final int translationTarget =
        math.min(math.max(ownSentenceCount, 0), translationSetSize);

    return NfPlanState(
      hasWords: words.isNotEmpty,
      reviewTarget:
          hasSchedule ? due : math.min(words.length, unscheduledReviewTarget),
      // Only a real schedule can say the reviewing is finished. Without one
      // there is nothing to be finished, and claiming otherwise would tell a
      // learner with a fresh deck that they were done before they began.
      reviewDone: hasSchedule && due == 0,
      newTarget: newTarget,
      learnedToday: learnedToday,
      learnDone: learnedToday >= newTarget,
      translationTarget: translationTarget,
      // A step with nothing in it is not a step that has been completed. With
      // no sentences of their own there is no set to translate, so this stays
      // false and the row keeps its prompt instead of a check mark.
      translationDone:
          translationTarget > 0 && translationsToday >= translationTarget,
    );
  }
}
