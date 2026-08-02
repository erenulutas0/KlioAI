import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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
        await _noteIfServerDailyReminder(initialMessage);
        await LocalReminderService.handleNotificationOpened(
          source: 'fcm_launch',
          payload: _routePayload(initialMessage),
        );
      }

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        // Also counted here, not just on the foreground path: a reminder aimed at 20:00 is
        // most often delivered while the app is closed, so the tap is the only evidence the
        // app gets that the server reached this device.
        unawaited(_noteIfServerDailyReminder(message));
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

    await _noteIfServerDailyReminder(message);
    await LocalReminderService().showRemoteNotification(
      title: title,
      body: body,
      payload: _routePayload(message),
    );
  }

  /// Tells the local scheduler that the server is covering the evening reminder.
  ///
  /// Both channels aim at 20:00 in the learner's own time, and the server's version is the
  /// better one — it is built when it is sent, so it can count the words actually due and
  /// stay silent for somebody who already practised. The local schedule steps aside once it
  /// sees one of these arrive, and takes the job back if they stop coming.
  static Future<void> _noteIfServerDailyReminder(RemoteMessage message) async {
    if (message.data['type']?.toString() != 'daily_reminder') {
      return;
    }
    try {
      await LocalReminderService.noteServerReminderDelivered();
    } catch (e) {
      // A bookkeeping failure must not swallow the notification itself. The worst case is
      // that the local reminder keeps running alongside, which is the behaviour we already
      // had.
      debugPrint('Could not record server reminder delivery: $e');
    }
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
      timezone: await _ianaTimezone(),
      dailyRemindersEnabled: dailyRemindersEnabled,
    );

    await prefs.setString(_lastRegisteredTokenKey, token);
    await prefs.setString(_lastRegisteredDayKey, today);
    await prefs.setString(_lastRegisteredAppVersionKey, appVersion);
    await AnalyticsService.logPushTokenRegistered(platform: platform);
  }

  /// The device's IANA zone id, e.g. `Europe/Istanbul`.
  ///
  /// This used to send `DateTime.now().timeZoneName`, which is an abbreviation, not an
  /// identifier — `GMT+03:00` on Android, `CEST` in Berlin in August, `+03` elsewhere. The
  /// backend resolves this with `ZoneId.of()` to decide when it is evening for this
  /// learner, and `ZoneId.of("CEST")` throws. The failure is silent and one-directional:
  /// every unparseable zone falls back to Istanbul, so the whole point of storing a
  /// per-device timezone quietly evaporates for exactly the learners who are not in Turkey.
  ///
  /// Worse, the abbreviation changes across a DST boundary while the zone does not, so a
  /// value that happened to parse in winter can stop parsing in summer.
  static Future<String> _ianaTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      final identifier = timezone.identifier.trim();
      if (identifier.isNotEmpty) {
        return identifier;
      }
    } catch (e) {
      debugPrint('Local timezone lookup failed: $e');
    }
    // The backend applies the same fallback, but sending it explicitly means a stored row
    // says what was actually known rather than looking like a real reading.
    return 'Europe/Istanbul';
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
