import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Decides when to ask a learner how the app is going, and remembers what they said.
///
/// The app has almost no users and no reviews, so its store rating is its most fragile
/// asset — and until now the store review prompt fired blind on the third completed
/// practice, before anyone had ever asked whether the learner was getting anything out of
/// it. For three months the thing they were being asked to rate was serving hardcoded
/// template sentences. Soliciting a public rating in that state is asking for the one-star
/// review you cannot take back.
///
/// So the private question comes first. Somebody who says it is working is a good candidate
/// for the store; somebody who says it is not has just told us something no dashboard could,
/// and the right response to that is a text box, not a rating request.
///
/// The counting deliberately reuses the completion counter the review prompt already keeps,
/// so the two cannot drift apart and a learner cannot be asked twice for the same session.
class FeedbackPromptService {
  /// Practice completions before asking. Far enough in to have an opinion, early enough
  /// that the opinion is still about a first impression we can act on.
  static const int askAfterCompletions = 3;

  /// If they said "not really" and we fixed things, one more ask is fair. Two is nagging.
  static const int askAgainAfterCompletions = 12;

  static const String completionCountKey =
      'in_app_review:practice_completion_count';
  static const String answeredAtKey = 'feedback_prompt:answered_at';
  static const String lastAnswerKey = 'feedback_prompt:last_answer';
  static const String answeredAtCompletionKey =
      'feedback_prompt:answered_at_completion';
  static const String dismissedKey = 'feedback_prompt:dismissed';

  /// What the learner said. Only [good] earns a store review request.
  static const String answerGood = 'good';
  static const String answerMixed = 'mixed';
  static const String answerBad = 'bad';

  /// Whether to show the question now, given how many practices are finished.
  ///
  /// Takes the count rather than reading it, so the caller increments once and both this and
  /// the review prompt see the same number.
  Future<bool> shouldAsk(int completions) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Someone who closed the question without answering has answered it.
      if (prefs.getBool(dismissedKey) ?? false) {
        return false;
      }

      final lastAnswer = prefs.getString(lastAnswerKey);
      if (lastAnswer == null) {
        return completions >= askAfterCompletions;
      }

      // A happy answer is the end of it — they have been sent to the store and asking
      // again gains nothing.
      if (lastAnswer == answerGood) {
        return false;
      }

      // An unhappy one is worth revisiting once, much later, because the answer is about
      // a version of the app that no longer exists by then.
      final askedAt = prefs.getInt(answeredAtCompletionKey) ?? 0;
      return completions - askedAt >= askAgainAfterCompletions;
    } catch (e) {
      // Never let bookkeeping break a session that just ended well.
      debugPrint('Feedback prompt check skipped: $e');
      return false;
    }
  }

  Future<void> recordAnswer(String answer, int completions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastAnswerKey, answer);
      await prefs.setString(answeredAtKey, DateTime.now().toIso8601String());
      await prefs.setInt(answeredAtCompletionKey, completions);
    } catch (e) {
      debugPrint('Feedback answer not recorded: $e');
    }
  }

  /// Closed without answering. Treated as a "no" to being asked, permanently.
  Future<void> recordDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(dismissedKey, true);
    } catch (e) {
      debugPrint('Feedback dismissal not recorded: $e');
    }
  }

  /// The count the review prompt is also working from.
  Future<int> completions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(completionCountKey) ?? 0;
    } catch (e) {
      debugPrint('Completion count unavailable: $e');
      return 0;
    }
  }
}
