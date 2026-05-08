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

  static Future<void> logAppOpen({String source = 'cold_start'}) {
    return logEvent('app_open', parameters: {'source': source});
  }

  static Future<void> logOnboardingStarted({String source = 'first_run'}) {
    return logEvent('onboarding_started', parameters: {'source': source});
  }

  static Future<void> logOnboardingCompleted({String source = 'first_run'}) {
    return logEvent('onboarding_completed', parameters: {'source': source});
  }

  static Future<void> logActivationCardShown({
    required int completedSteps,
    required int wordCount,
    required int sentenceCount,
  }) {
    return _logOnce(
      key: 'analytics:first_session_activation_card_shown',
      eventName: 'first_session_activation_card_shown',
      parameters: {
        'completed_steps': completedSteps,
        'word_count': wordCount,
        'sentence_count': sentenceCount,
      },
    );
  }

  static Future<void> logActivationLevelSelected({
    required String level,
  }) {
    return _logOnce(
      key: 'analytics:first_session_level_selected',
      eventName: 'first_session_level_selected',
      parameters: {'level': level},
    );
  }

  static Future<void> logActivationStepCompleted({
    required String step,
    int? completedSteps,
  }) {
    return _logOnce(
      key: 'analytics:first_session_step_completed:$step',
      eventName: 'first_session_step_completed',
      parameters: {
        'step': step,
        if (completedSteps != null) 'completed_steps': completedSteps,
      },
    );
  }

  static Future<void> logActivationCompleted({
    required int wordCount,
    required int sentenceCount,
  }) {
    return _logOnce(
      key: 'analytics:first_session_activation_completed',
      eventName: 'first_session_activation_completed',
      parameters: {
        'word_count': wordCount,
        'sentence_count': sentenceCount,
      },
    );
  }

  static Future<void> logActivationDismissed({
    required int completedSteps,
  }) {
    return logEvent(
      'first_session_activation_dismissed',
      parameters: {'completed_steps': completedSteps},
    );
  }

  static Future<void> logProgressiveUnlockBlocked({
    required String mode,
    required String source,
  }) {
    return logEvent(
      'progressive_unlock_blocked',
      parameters: {
        'mode': mode,
        'source': source,
      },
    );
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
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('activation:practice_completed', true);
    } catch (e) {
      debugPrint('Activation practice completion marker failed: $e');
    }
    await logEvent(
      'practice_completed',
      parameters: {
        'type': type,
        if (level != null && level.isNotEmpty) 'level': level,
        if (score != null) 'score': score,
        if (totalQuestions != null) 'total_questions': totalQuestions,
      },
    );
  }

  static Future<void> logPracticeStarted({
    required String type,
    String? level,
    String? subMode,
  }) {
    return logEvent(
      'practice_started',
      parameters: {
        'type': type,
        if (level != null && level.isNotEmpty) 'level': level,
        if (subMode != null && subMode.isNotEmpty) 'sub_mode': subMode,
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

  static Future<void> logPurchaseFailed({
    String? planName,
    String? reason,
  }) {
    return logEvent(
      'purchase_failed',
      parameters: {
        if (planName != null && planName.isNotEmpty) 'plan_name': planName,
        if (reason != null && reason.isNotEmpty) 'reason': _limit(reason, 90),
      },
    );
  }

  static Future<void> logTrialSnapshot({
    required bool trialActive,
    int? daysRemaining,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasActive = prefs.getBool('analytics:trial_was_active') ?? false;
      if (trialActive) {
        if (prefs.getBool('analytics:trial_started') != true) {
          await logEvent(
            'trial_started',
            parameters: {
              if (daysRemaining != null) 'days_remaining': daysRemaining,
            },
          );
          await prefs.setBool('analytics:trial_started', true);
        }
        await prefs.setBool('analytics:trial_was_active', true);
        return;
      }

      if (wasActive && prefs.getBool('analytics:trial_expired') != true) {
        await logEvent('trial_expired');
        await prefs.setBool('analytics:trial_expired', true);
      }
      await prefs.setBool('analytics:trial_was_active', false);
    } catch (e) {
      debugPrint('Analytics trial snapshot failed: $e');
    }
  }

  static Future<void> logSupportTicketCreated({required String type}) {
    return logEvent('support_ticket_created', parameters: {'type': type});
  }

  static Future<void> logReviewPromptRequested({required int completions}) {
    return logEvent(
      'review_prompt_requested',
      parameters: {'practice_completions': completions},
    );
  }

  static Future<void> logNotificationPreferenceChanged({
    required String type,
    required bool enabled,
  }) {
    return logEvent(
      'notification_preference_changed',
      parameters: {
        'type': type,
        'enabled': enabled,
      },
    );
  }

  static Future<void> logNotificationOpened({
    required String source,
    String? payload,
  }) {
    return logEvent(
      'notification_opened',
      parameters: {
        'source': source,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      },
    );
  }

  static Future<void> logPushTokenRegistered({required String platform}) {
    return logEvent(
      'push_token_registered',
      parameters: {'platform': platform},
    );
  }

  static Future<void> logPushTokenRegistrationFailed({required String reason}) {
    return logEvent(
      'push_token_registration_failed',
      parameters: {'reason': _limit(reason, 90)},
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

  static String _limit(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}
