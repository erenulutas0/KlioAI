import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// Asks the store for a rating — but only for a learner who has already said, in the app,
/// that it is working for them.
///
/// This used to fire on the third completed practice regardless. That is a rating request
/// sent to someone we had never asked anything, about an app that for three months served
/// hardcoded template sentences as if a model had written them. With almost no users and no
/// reviews yet, a single one-star review is a large and permanent fraction of the rating,
/// and there is no way to take it back. See [FeedbackPromptService] for the question that
/// now comes first.
class InAppReviewService {
  static const int _completionThreshold = 3;
  static const String _completionCountKey =
      'in_app_review:practice_completion_count';
  static const String _requestedKey = 'in_app_review:requested';

  /// Counts one finished practice and returns the new total.
  ///
  /// Counting is all this does now. Whether anything is shown is decided by the caller,
  /// which is the only place that knows what the learner just said.
  Future<int> recordPracticeCompletion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completions = (prefs.getInt(_completionCountKey) ?? 0) + 1;
      await prefs.setInt(_completionCountKey, completions);
      return completions;
    } catch (e) {
      debugPrint('Practice completion not counted: $e');
      return 0;
    }
  }

  /// Whether a learner is far enough in for a rating request to be reasonable at all.
  Future<bool> isEligibleForStorePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_requestedKey) ?? false) {
        return false;
      }
      return (prefs.getInt(_completionCountKey) ?? 0) >= _completionThreshold;
    } catch (e) {
      debugPrint('Store prompt eligibility unavailable: $e');
      return false;
    }
  }

  /// Shows the store's rating sheet. Call only after the learner has said the app is
  /// working for them.
  Future<void> requestStoreReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_requestedKey) ?? false) {
        return;
      }

      final review = InAppReview.instance;
      if (!await review.isAvailable()) {
        return;
      }

      await AnalyticsService.logReviewPromptRequested(
        completions: prefs.getInt(_completionCountKey) ?? 0,
      );
      await review.requestReview();
      await prefs.setBool(_requestedKey, true);
    } catch (e) {
      debugPrint('In-app review prompt skipped: $e');
    }
  }
}
