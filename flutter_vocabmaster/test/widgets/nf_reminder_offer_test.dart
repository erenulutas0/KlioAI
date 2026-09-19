import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/widgets/nf_reminder_offer.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';

/// Who gets asked about notifications, and when.
///
/// The system prompt used to open at launch, before the app had said anything. Android 13
/// closes the setting after two refusals, and the result was 12 push tokens across 105
/// accounts: the reminders that exist to bring people back could not reach nine in ten of
/// them. The prompt is now opened only by somebody who has just said yes to being reminded,
/// and these pin who is asked and how often.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  final DateTime start = DateTime(2026, 9, 20, 21);

  /// The plugin answers this from the Android side; here it is whatever a test needs.
  void notificationsAllowed(bool allowed) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel,
            (MethodCall call) async {
      if (call.method == 'areNotificationsEnabled') {
        return allowed;
      }
      return null;
    });
  }

  // The permission is an Android question, and the plugin answers it only when the platform
  // says Android. A widget test may not leave this set, so it is switched on per test rather
  // than in setUp.
  void onAndroid() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    notificationsAllowed(false);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  test('somebody who has not been asked is asked', () async {
    onAndroid();
    expect(await NfReminderPromptSchedule.shouldAsk(now: start), isTrue);
  });

  test('and not again for days', () async {
    onAndroid();
    await NfReminderPromptSchedule.recordAsked(now: start);

    expect(
        await NfReminderPromptSchedule.shouldAsk(
            now: start.add(const Duration(days: 1))),
        isFalse);
    expect(
        await NfReminderPromptSchedule.shouldAsk(
            now: start.add(const Duration(days: 4))),
        isTrue);
  });

  test('twice, and then never', () async {
    onAndroid();
    DateTime now = start;
    for (int i = 0; i < NfReminderPromptSchedule.maxAsks; i++) {
      await NfReminderPromptSchedule.recordAsked(now: now);
      now = now.add(const Duration(days: 7));
    }

    expect(await NfReminderPromptSchedule.shouldAsk(now: now), isFalse);
    expect(
        await NfReminderPromptSchedule.shouldAsk(
            now: now.add(const Duration(days: 365))),
        isFalse);
  });

  test('somebody who already allows notifications is not asked at all', () async {
    onAndroid();
    notificationsAllowed(true);

    expect(await NfReminderPromptSchedule.shouldAsk(now: start), isFalse,
        reason: 'the offer leads to a prompt that has nothing left to ask');
  });

  testWidgets('the offer says what will arrive, and takes no for an answer',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const NfReminderOfferSheet(reason: 'test'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
        find.text(AppLocalizations(const Locale('tr')).t('reminder.offer.title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reminder-offer-yes')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('reminder-offer-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('reminder-offer-yes')), findsNothing);
  });

  test('nothing asks for the permission before there is something to remind about', () {
    // The whole change in one line: the push service registers a device that has already
    // allowed notifications and never opens the prompt itself.
    final String source =
        File('lib/services/push_token_service.dart').readAsStringSync();

    expect(source.contains('requestPermission('), isFalse,
        reason: 'the system prompt is back at app start, where nine in ten '
            'people refuse it');
    expect(source, contains('_hasNotificationPermission'));
  });
}
