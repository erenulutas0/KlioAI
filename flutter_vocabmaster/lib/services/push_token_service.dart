import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'local_reminder_service.dart';

class PushTokenService {
  PushTokenService({
    FirebaseMessaging? messaging,
    ApiService? apiService,
    AuthService? authService,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _apiService = apiService ?? ApiService(),
        _authService = authService ?? AuthService();

  static const _lastRegisteredTokenKey = 'push:last_registered_token';
  static const _lastRegisteredDayKey = 'push:last_registered_day';
  static bool _initialized = false;

  final FirebaseMessaging _messaging;
  final ApiService _apiService;
  final AuthService _authService;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }
    _initialized = true;

    try {
      await _registerCurrentToken(force: false);
      _messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token, force: true));
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        await AnalyticsService.logNotificationOpened(
          source: 'fcm_launch',
          payload: _payloadName(initialMessage),
        );
      }

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        unawaited(
          AnalyticsService.logNotificationOpened(
            source: 'fcm_tap',
            payload: _payloadName(message),
          ),
        );
      });
    } catch (e) {
      await AnalyticsService.logPushTokenRegistrationFailed(reason: '$e');
      debugPrint('Push token service disabled: $e');
    }
  }

  Future<void> refreshTokenRegistration() async {
    await _registerCurrentToken(force: true);
  }

  Future<void> _registerCurrentToken({required bool force}) async {
    if (!await _authService.isLoggedIn()) {
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _registerToken(token, force: force);
  }

  Future<void> _registerToken(String token, {required bool force}) async {
    if (!await _authService.isLoggedIn()) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final lastToken = prefs.getString(_lastRegisteredTokenKey);
    final lastDay = prefs.getString(_lastRegisteredDayKey);
    if (!force && lastToken == token && lastDay == today) {
      return;
    }

    final deviceId = await _authService.getOrCreateDeviceId();
    final platform = _platformName();
    final dailyRemindersEnabled =
        await LocalReminderService().isDailyReminderEnabled();
    await _apiService.registerPushToken(
      token: token,
      platform: platform,
      deviceId: deviceId,
      locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      dailyRemindersEnabled: dailyRemindersEnabled,
    );

    await prefs.setString(_lastRegisteredTokenKey, token);
    await prefs.setString(_lastRegisteredDayKey, today);
    await AnalyticsService.logPushTokenRegistered(platform: platform);
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  String _payloadName(RemoteMessage message) {
    final type = message.data['type']?.toString();
    if (type != null && type.isNotEmpty) {
      return type;
    }
    return message.messageId ?? 'fcm';
  }
}
