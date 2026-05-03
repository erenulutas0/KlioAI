import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'analytics_service.dart';

class LocalReminderService {
  static const String dailyReminderKey = 'notifications:daily_reminder_enabled';
  static const String lastOpenedPayloadKey = 'notifications:last_opened_payload';
  static const String lastOpenedAtKey = 'notifications:last_opened_at';
  static const int _dailyReminderId = 31001;
  static const int _dailyReminderHour = 20;
  static const int _dailyReminderMinute = 0;
  static const String _channelId = 'daily_learning_reminders';
  static const String _channelName = 'Daily learning reminders';
  static const String _channelDescription =
      'Daily reminders to continue vocabulary practice.';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          unawaited(
            _handleNotificationOpened(
              source: 'tap',
              payload: response.payload,
            ),
          );
        },
      );
      _initialized = true;
      await _logLaunchFromNotificationIfNeeded();
      await refreshScheduledReminders();
    } catch (e) {
      debugPrint('Local reminder initialization skipped: $e');
    }
  }

  Future<bool> isDailyReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(dailyReminderKey) ?? false;
  }

  Future<bool> setDailyReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final permissionGranted = await _requestNotificationPermission();
      if (!permissionGranted) {
        await prefs.setBool(dailyReminderKey, false);
        await cancelDailyReminder();
        await AnalyticsService.logNotificationPreferenceChanged(
          type: 'daily_reminder',
          enabled: false,
        );
        return false;
      }
      await prefs.setBool(dailyReminderKey, true);
      await scheduleDailyReminder();
    } else {
      await prefs.setBool(dailyReminderKey, false);
      await cancelDailyReminder();
    }

    await AnalyticsService.logNotificationPreferenceChanged(
      type: 'daily_reminder',
      enabled: enabled,
    );
    return enabled;
  }

  Future<void> refreshScheduledReminders() async {
    if (await isDailyReminderEnabled()) {
      await scheduleDailyReminder();
    }
  }

  Future<void> scheduleDailyReminder() async {
    await initialize();
    await _notifications.zonedSchedule(
      _dailyReminderId,
      'KlioAI',
      'A quick practice session is ready for today.',
      _nextReminderTime(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_practice',
    );
  }

  Future<void> cancelDailyReminder() async {
    await _notifications.cancel(_dailyReminderId);
  }

  Future<void> _logLaunchFromNotificationIfNeeded() async {
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true) {
      await _handleNotificationOpened(
        source: 'launch',
        payload: response?.payload,
      );
    }
  }

  static Future<void> _handleNotificationOpened({
    required String source,
    String? payload,
  }) async {
    try {
      await AnalyticsService.logNotificationOpened(
        source: source,
        payload: payload,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastOpenedPayloadKey, payload ?? '');
      await prefs.setString(
        lastOpenedAtKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('Notification open tracking skipped: $e');
    }
  }

  Future<bool> _requestNotificationPermission() async {
    try {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted =
          await android?.requestNotificationsPermission() ?? true;

      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;

      final mac = _notifications.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final macGranted = await mac?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;

      return androidGranted && iosGranted && macGranted;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  tz.TZDateTime _nextReminderTime() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _dailyReminderHour,
      _dailyReminderMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
