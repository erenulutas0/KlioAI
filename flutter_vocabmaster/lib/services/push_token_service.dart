import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
    @visibleForTesting bool skipMessagingInstance = false,
  })  : _messaging = skipMessagingInstance
            ? null
            : (messaging ?? FirebaseMessaging.instance),
        _apiService = apiService ?? ApiService(),
        _authService = authService ?? AuthService(),
        _skipMessagingInstance = skipMessagingInstance;

  static const _lastRegisteredTokenKey = 'push:last_registered_token';
  static const _lastRegisteredDayKey = 'push:last_registered_day';
  static const _lastRegisteredAppVersionKey =
      'push:last_registered_app_version';
  static bool _initialized = false;

  final FirebaseMessaging? _messaging;
  final ApiService _apiService;
  final AuthService _authService;
  final bool _skipMessagingInstance;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || _skipMessagingInstance) {
      return;
    }
    _initialized = true;

    try {
      await _requestNotificationPermission();
      await _registerCurrentToken(force: false);
      _messaging!.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token, force: true));
      });
      FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showForegroundNotification(message));
      });

      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        await LocalReminderService.handleNotificationOpened(
          source: 'fcm_launch',
          payload: _routePayload(initialMessage),
        );
      }

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        unawaited(
          LocalReminderService.handleNotificationOpened(
            source: 'fcm_tap',
            payload: _routePayload(message),
          ),
        );
      });
    } catch (e) {
      await AnalyticsService.logPushTokenRegistrationFailed(reason: '$e');
      debugPrint('Push token service disabled: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await LocalReminderService().requestNotificationPermission();
    } catch (e) {
      debugPrint('Push notification permission skipped: $e');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'KlioAI';
    final body = notification?.body ??
        message.data['body']?.toString() ??
        'A KlioAI notification is ready.';

    await LocalReminderService().showRemoteNotification(
      title: title,
      body: body,
      payload: _routePayload(message),
    );
  }

  Future<void> refreshTokenRegistration() async {
    await _registerCurrentToken(force: true);
  }

  @visibleForTesting
  Future<void> registerTokenForTesting(String token, {bool force = false}) {
    return _registerToken(token, force: force);
  }

  Future<void> _registerCurrentToken({required bool force}) async {
    if (!await _authService.isLoggedIn()) {
      return;
    }

    final token = await _messaging!.getToken();
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
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    final lastAppVersion = prefs.getString(_lastRegisteredAppVersionKey);
    if (!force &&
        lastToken == token &&
        lastDay == today &&
        lastAppVersion == appVersion) {
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
      appVersion: appVersion,
      locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      timezone: DateTime.now().timeZoneName,
      dailyRemindersEnabled: dailyRemindersEnabled,
    );

    await prefs.setString(_lastRegisteredTokenKey, token);
    await prefs.setString(_lastRegisteredDayKey, today);
    await prefs.setString(_lastRegisteredAppVersionKey, appVersion);
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

  String _routePayload(RemoteMessage message) {
    final route = message.data['route']?.toString();
    if (route != null && route.trim().isNotEmpty) {
      return route.trim();
    }
    return _payloadName(message);
  }
}
