import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

class InAppReviewService {
  static const int _completionThreshold = 3;
  static const String _completionCountKey =
      'in_app_review:practice_completion_count';
  static const String _requestedKey = 'in_app_review:requested';

  Future<void> recordPracticeCompletion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyRequested = prefs.getBool(_requestedKey) ?? false;
      if (alreadyRequested) {
        return;
      }

      final completions = (prefs.getInt(_completionCountKey) ?? 0) + 1;
      await prefs.setInt(_completionCountKey, completions);
      if (completions < _completionThreshold) {
        return;
      }

      final review = InAppReview.instance;
      final available = await review.isAvailable();
      if (!available) {
        return;
      }

      await AnalyticsService.logReviewPromptRequested(
        completions: completions,
      );
      await review.requestReview();
      await prefs.setBool(_requestedKey, true);
    } catch (e) {
      debugPrint('In-app review prompt skipped: $e');
    }
  }
}
