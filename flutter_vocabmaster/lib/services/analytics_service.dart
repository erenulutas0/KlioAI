import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static bool _enabled = false;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static FirebaseAnalyticsObserver get navigatorObserver =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_enabled) return;
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('Analytics logEvent failed for $name: $e');
    }
  }

  static Future<void> setUserId(String? userId) async {
    if (!_enabled) return;
    try {
      await _analytics.setUserId(id: userId);
    } catch (e) {
      debugPrint('Analytics setUserId failed: $e');
    }
  }

  static Future<void> setUserProperty(String name, String? value) async {
    if (!_enabled) return;
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (e) {
      debugPrint('Analytics setUserProperty failed for $name: $e');
    }
  }

  static Future<void> logScreenView(
    String screenName, {
    String? screenClass,
  }) async {
    if (!_enabled) return;
    try {
      await _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      );
    } catch (e) {
      debugPrint('Analytics logScreenView failed for $screenName: $e');
    }
  }

  static Future<void> logSignupCompleted({
    String method = 'email',
    String? userId,
  }) async {
    await setUserId(userId);
    await setUserProperty('auth_method', method);
    await logEvent('signup_completed', parameters: {'method': method});
  }

  static Future<void> logLoginCompleted({
    String method = 'email',
    String? userId,
  }) async {
    await setUserId(userId);
    await setUserProperty('auth_method', method);
    await logEvent('login_completed', parameters: {'method': method});
  }

  static Future<void> logFirstWordAdded({
    String? source,
    String? difficulty,
  }) {
    return _logOnce(
      key: 'analytics:first_word_added',
      eventName: 'first_word_added',
      parameters: {
        if (source != null && source.isNotEmpty) 'source': source,
        if (difficulty != null && difficulty.isNotEmpty)
          'difficulty': difficulty,
      },
    );
  }

  static Future<void> logFirstSentenceAdded({
    String? difficulty,
  }) {
    return _logOnce(
      key: 'analytics:first_sentence_added',
      eventName: 'first_sentence_added',
      parameters: {
        if (difficulty != null && difficulty.isNotEmpty)
          'difficulty': difficulty,
      },
    );
  }

  static Future<void> logFirstAiUse({
    String? feature,
  }) {
    return _logOnce(
      key: 'analytics:first_ai_use',
      eventName: 'first_ai_use',
      parameters: {
        if (feature != null && feature.isNotEmpty) 'feature': feature,
      },
    );
  }

  static Future<void> logPracticeCompleted({
    required String type,
    String? level,
    int? score,
    int? totalQuestions,
  }) {
    return logEvent(
      'practice_completed',
      parameters: {
        'type': type,
        if (level != null && level.isNotEmpty) 'level': level,
        if (score != null) 'score': score,
        if (totalQuestions != null) 'total_questions': totalQuestions,
      },
    );
  }

  static Future<void> logPaywallShown({String source = 'unknown'}) {
    return logEvent('paywall_shown', parameters: {'source': source});
  }

  static Future<void> logPurchaseStarted({
    required String planName,
    String? currency,
    double? price,
  }) {
    return logEvent(
      'purchase_started',
      parameters: {
        'plan_name': planName,
        if (currency != null && currency.isNotEmpty) 'currency': currency,
        if (price != null) 'price': price,
      },
    );
  }

  static Future<void> logPurchaseCompleted({String? planName}) {
    return logEvent(
      'purchase_completed',
      parameters: {
        if (planName != null && planName.isNotEmpty) 'plan_name': planName,
      },
    );
  }

  static Future<void> _logOnce({
    required String key,
    required String eventName,
    Map<String, Object>? parameters,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) {
        return;
      }
      await logEvent(eventName, parameters: parameters);
      await prefs.setBool(key, true);
    } catch (e) {
      debugPrint('Analytics one-shot event failed for $eventName: $e');
    }
  }
}
