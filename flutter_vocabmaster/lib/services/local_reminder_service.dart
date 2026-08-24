import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../frontend_newest/nf_shell.dart';
import '../widgets/theme_side_tab.dart';
import 'analytics_service.dart';
import 'locale_text_service.dart';

class LocalReminderService {
  static const String dailyReminderKey = 'notifications:daily_reminder_enabled';

  /// Each reminder answers to its own switch.
  ///
  /// The settings screen has always shown separate toggles for streak and subscription
  /// reminders, and sent all of them to the backend for push — but locally every scheduler
  /// checked [dailyReminderKey]. Turning off streak reminders in settings did nothing to
  /// the streak reminder actually arriving on the phone, which is the difference between
  /// a reminder and being pestered.
  static const String streakGuardKey = 'notifications:streak_guard_enabled';
  static const String subscriptionAlertKey =
      'notifications:subscription_alert_enabled';
  static const String wordRecallKey = 'notifications:word_recall_enabled';

  /// When the server's daily reminder last actually arrived on this device.
  static const String _serverReminderSeenAtKey =
      'notifications:server_reminder_seen_at';

  /// How long one delivered server reminder is taken as proof the server owns the slot.
  /// Long enough to cover a missed evening, short enough that a broken push pipeline hands
  /// the job back before the learner notices the silence.
  static const Duration _serverReminderTrustWindow = Duration(days: 3);

  static const String lastOpenedPayloadKey =
      'notifications:last_opened_payload';
  static const String lastOpenedAtKey = 'notifications:last_opened_at';
  static const Duration _pendingRouteMaxAge = Duration(minutes: 5);
  static const int _dailyReminderId = 31001;
  static const int _streakGuardReminderId = 31002;
  static const int _trialExpiryReminderId = 31003;
  static const int _wordRecallReminderId = 31004;
  static const int _remoteNotificationBaseId = 32000;
  static const int _dailyReminderHour = 20;
  static const int _dailyReminderMinute = 0;
  static const int _streakGuardHour = 20;
  static const int _streakGuardMinute = 30;
  static const int _trialReminderHour = 10;
  static const int _trialReminderMinute = 0;

  /// Deliberately in the middle of the day, well away from the 20:00 practice nudge and
  /// the 20:30 streak guard. Three notifications inside half an hour is how a reminder
  /// turns into nagging; spreading them means a user who has all three on still only hears
  /// from the app twice in an evening.
  static const int _wordRecallHour = 13;
  static const int _wordRecallMinute = 30;
  static const String _channelId = 'daily_learning_reminders';
  static const String _channelName = 'Daily learning reminders';
  static const String _channelDescription =
      'Daily reminders to continue vocabulary practice.';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Points the scheduler at the timezone the phone is actually in.
  ///
  /// Every reminder used to be scheduled in Europe/Istanbul regardless of where the user
  /// was, so a "20:00 study reminder" arrived at 22:00 in Jakarta and 18:00 in Berlin. The
  /// device zone is what the user set their day by, so it is what the schedule must follow.
  ///
  /// Falls back to Istanbul rather than UTC if the lookup fails: for the existing user base
  /// that is the closest guess, and it keeps the previous behaviour rather than shifting
  /// everyone's reminders by three hours on a lookup error.
  Future<void> _useDeviceTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Device timezone lookup failed, keeping Europe/Istanbul: $e');
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      tz.initializeTimeZones();
      await _useDeviceTimeZone();

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
            handleNotificationOpened(
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
    // Varsayılan AÇIK (opt-out): hatırlatıcılar retention'ın temel direği ve
    // gerçek kapı zaten OS bildirim izni (Android 13+ istemi). Kullanıcının
    // ayarlardan verdiği açık "kapat" kararı (stored false) her zaman korunur.
    return prefs.getBool(dailyReminderKey) ?? true;
  }

  /// Reads one of the per-reminder switches.
  ///
  /// Defaults to on, matching [isDailyReminderEnabled]: the real gate is the OS permission
  /// prompt, and an explicit "off" stored by the user is always honoured.
  Future<bool> _isEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true;
  }

  Future<bool> isStreakGuardEnabled() => _isEnabled(streakGuardKey);

  Future<bool> isSubscriptionAlertEnabled() => _isEnabled(subscriptionAlertKey);

  Future<bool> isWordRecallEnabled() => _isEnabled(wordRecallKey);

  /// Stores a per-reminder switch and cancels anything already scheduled when it goes off.
  /// Turning one off has to take effect on the notification already sitting in the OS
  /// queue, not just on the next one that would have been scheduled.
  Future<void> setReminderEnabled(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
    if (!enabled) {
      if (key == streakGuardKey) await cancelStreakGuardReminder();
      if (key == subscriptionAlertKey) await cancelTrialExpiryReminder();
      if (key == wordRecallKey) await cancelWordRecallReminder();
    }
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

  Future<bool> requestNotificationPermission() {
    return _requestNotificationPermission();
  }

  Future<void> showRemoteNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    if (title.trim().isEmpty && body.trim().isEmpty) {
      return;
    }

    final id = _remoteNotificationBaseId +
        DateTime.now().millisecondsSinceEpoch.remainder(1000);
    await _notifications.show(
      id,
      title.trim().isEmpty ? 'KlioAI' : title.trim(),
      body.trim().isEmpty ? null : body.trim(),
      _notificationDetails(),
      payload: payload,
    );
  }

  Future<void> refreshScheduledReminders() async {
    if (await isDailyReminderEnabled()) {
      await scheduleDailyReminder();
      await scheduleStreakGuardReminder();
    }
  }

  /// Records that the server's own daily reminder reached this device.
  ///
  /// See [scheduleDailyReminder] for why this matters.
  static Future<void> noteServerReminderDelivered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _serverReminderSeenAtKey, DateTime.now().toIso8601String());
  }

  /// Whether the server has delivered a daily reminder recently enough to own the slot.
  static Future<bool> _serverIsDeliveringReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_serverReminderSeenAtKey);
    if (raw == null || raw.isEmpty) {
      return false;
    }
    final seenAt = DateTime.tryParse(raw);
    if (seenAt == null) {
      return false;
    }
    return DateTime.now().difference(seenAt) < _serverReminderTrustWindow;
  }

  /// The offline fallback for the evening reminder — not the primary one.
  ///
  /// This fires from a schedule set days in advance, so its text is frozen at the moment it
  /// is armed. It cannot say how many words are actually due tonight and it cannot know
  /// whether the learner practised this afternoon, because neither of those was true yet
  /// when it was scheduled. The server reminder can: it decides at send time, counts the
  /// words that are really waiting, and stays quiet for somebody who has already studied.
  ///
  /// So when the server is demonstrably doing that job, this one gets out of the way — both
  /// were aimed at 20:00 local and would otherwise arrive together, saying roughly the same
  /// thing twice. The test is "has a server reminder actually arrived recently", not "is
  /// push configured": configuration can claim a delivery that never happens, and standing
  /// down for a channel that is silent would leave the learner with no reminder at all. If
  /// the server stops, this resumes on its own within [_serverReminderTrustWindow].
  Future<void> scheduleDailyReminder() async {
    await initialize();

    if (await _serverIsDeliveringReminders()) {
      await _notifications.cancel(_dailyReminderId);
      return;
    }

    await _notifications.zonedSchedule(
      _dailyReminderId,
      'KlioAI',
      // The old copy was one hardcoded English sentence sent to an audience learning
      // English *from Turkish*. Being unable to read your own reminder is a strange way
      // to be reminded.
      LocaleTextService.pick(
        'Bugünün pratiği seni bekliyor.',
        'A quick practice session is ready for today.',
      ),
      _nextReminderTime(),
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_practice',
    );
  }

  Future<void> scheduleStreakGuardReminder() async {
    await initialize();
    // Its own switch, not the daily one. These were the same check, so the streak toggle
    // in settings had no effect on the streak reminder.
    if (!await isStreakGuardEnabled()) {
      await cancelStreakGuardReminder();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt('current_streak') ?? 0;
    final lastActivityDate = prefs.getString('last_activity_date');
    if (streak <= 0 || lastActivityDate == null || lastActivityDate.isEmpty) {
      await cancelStreakGuardReminder();
      return;
    }

    final scheduled = _nextStreakGuardTime(lastActivityDate);
    if (scheduled == null) {
      await cancelStreakGuardReminder();
      return;
    }

    await _notifications.zonedSchedule(
      _streakGuardReminderId,
      LocaleTextService.pick('Serini kaybetme', 'Keep your streak alive'),
      LocaleTextService.pick(
        'Kısa bir pratik $streak günlük serini korur.',
        'A short KlioAI practice today keeps your $streak-day streak safe.',
      ),
      scheduled,
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'streak_guard',
    );
  }

  Future<void> scheduleTrialExpiryReminder({
    required bool trialActive,
    int? daysRemaining,
  }) async {
    await initialize();
    if (!await isSubscriptionAlertEnabled() ||
        !trialActive ||
        daysRemaining == null ||
        daysRemaining <= 0) {
      await cancelTrialExpiryReminder();
      return;
    }

    await _notifications.zonedSchedule(
      _trialExpiryReminderId,
      LocaleTextService.pick(
        'Deneme sürenin sonuna yaklaşıyorsun',
        'Your KlioAI trial is ending soon',
      ),
      LocaleTextService.pick(
        'AI pratiğini kesintisiz kullanmak için $daysRemaining günün kaldı.',
        'You have $daysRemaining day${daysRemaining == 1 ? '' : 's'} left to use AI practice without interruption.',
      ),
      _trialExpiryReminderTime(daysRemaining),
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'trial_expiring',
    );
  }

  /// A daily nudge about one specific word, rather than a generic "come practise".
  ///
  /// Naming the word is the point: "What did *elaborate* mean?" is itself a retrieval
  /// attempt, so the notification does a little teaching even if it is never tapped. A
  /// generic reminder cannot do that.
  ///
  /// [word] is chosen by the caller, which knows the vocabulary; this service only knows
  /// how to schedule. [isTurkish] picks the copy language.
  ///
  /// One per day, at [_wordRecallHour], and only if the user has left the switch on.
  Future<void> scheduleWordRecallReminder({
    required String word,
    required bool isTurkish,
    String? wordId,
  }) async {
    await initialize();
    if (!await isWordRecallEnabled() || word.trim().isEmpty) {
      await cancelWordRecallReminder();
      return;
    }

    final trimmed = word.trim();
    // Two phrasings, alternating by day so the notification does not read like a form
    // letter. Both ask for recall rather than announcing something.
    final askMeaning = DateTime.now().day.isEven;
    final title = isTurkish ? 'Bunu hatirliyor musun?' : 'Do you remember this one?';
    final body = askMeaning
        ? (isTurkish
            ? '"$trimmed" ne demekti? Hatirlayip kontrol et.'
            : 'What did "$trimmed" mean? Try to recall, then check.')
        : (isTurkish
            ? '"$trimmed" kelimesini bir kez tekrar edelim mi?'
            : 'Shall we run through "$trimmed" once?');

    await _notifications.zonedSchedule(
      _wordRecallReminderId,
      title,
      body,
      _nextWordRecallTime(),
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: wordId == null ? 'word_recall' : 'word_recall:$wordId',
    );
  }

  tz.TZDateTime _nextWordRecallTime() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _wordRecallHour,
      _wordRecallMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> cancelWordRecallReminder() async {
    await _notifications.cancel(_wordRecallReminderId);
  }

  Future<void> cancelDailyReminder() async {
    await _notifications.cancel(_dailyReminderId);
  }

  Future<void> cancelStreakGuardReminder() async {
    await _notifications.cancel(_streakGuardReminderId);
  }

  Future<void> cancelTrialExpiryReminder() async {
    await _notifications.cancel(_trialExpiryReminderId);
  }

  Future<void> _logLaunchFromNotificationIfNeeded() async {
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true) {
      await handleNotificationOpened(
        source: 'launch',
        payload: response?.payload,
      );
    }
  }

  static Future<void> handleNotificationOpened({
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
      _navigateForPayload(payload);
    } catch (e) {
      debugPrint('Notification open tracking skipped: $e');
    }
  }

  static Future<String?> consumePendingNavigationPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(lastOpenedPayloadKey)?.trim();
    final openedAtRaw = prefs.getString(lastOpenedAtKey);

    await prefs.remove(lastOpenedPayloadKey);
    await prefs.remove(lastOpenedAtKey);

    if (payload == null || payload.isEmpty) {
      return null;
    }

    final openedAt = DateTime.tryParse(openedAtRaw ?? '');
    if (openedAt == null ||
        DateTime.now().difference(openedAt).abs() > _pendingRouteMaxAge) {
      return null;
    }

    return payload;
  }

  /// Handles a notification tapped while the app is already running.
  ///
  /// Every reminder this app sends means the same thing — there is something to
  /// do today — and Today is the screen that says what. So all four payloads
  /// land there, which is also what `NfShell` does with the stored payload on a
  /// cold start; the two paths agreeing is the point.
  ///
  /// This used to do two different and worse things. A practice reminder pushed
  /// `PracticePage`, a tab body that carries no app bar of its own, so it
  /// arrived on top of the shell with nothing on screen to get back with. A
  /// notification reminder called `pushAndRemoveUntil(..., (route) => false)`,
  /// which disposes the mounted shell and every tab's state with it — a learner
  /// mid-session lost the session.
  ///
  /// When no shell is mounted this does nothing on purpose. The payload was
  /// already written to `SharedPreferences` by the caller, and the shell reads
  /// it in `initState`, so a tap that arrives before sign-in is honoured after
  /// it instead of being obeyed by pushing past the login screen.
  static void _navigateForPayload(String? payload) {
    switch ((payload ?? '').trim().toLowerCase()) {
      case 'notifications':
      case 'admin_test':
      case 'daily_practice':
      case 'streak_guard':
        NfShell.showTodayIfMounted();
      default:
        break;
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

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }

  tz.TZDateTime? _nextStreakGuardTime(String lastActivityDate) {
    final parsed = DateTime.tryParse(lastActivityDate);
    if (parsed == null) {
      return null;
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      parsed.year,
      parsed.month,
      parsed.day,
      _streakGuardHour,
      _streakGuardMinute,
    ).add(const Duration(days: 1));

    if (!scheduled.isAfter(now)) {
      final sameDayLateReminder = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        23,
        0,
      );
      if (sameDayLateReminder.isAfter(now)) {
        scheduled = sameDayLateReminder;
      } else {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    }
    return scheduled;
  }

  tz.TZDateTime _trialExpiryReminderTime(int daysRemaining) {
    final now = tz.TZDateTime.now(tz.local);
    if (daysRemaining <= 2) {
      return now.add(const Duration(minutes: 10));
    }

    final targetDay = now.add(Duration(days: daysRemaining - 2));
    var scheduled = tz.TZDateTime(
      tz.local,
      targetDay.year,
      targetDay.month,
      targetDay.day,
      _trialReminderHour,
      _trialReminderMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
