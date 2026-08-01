import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/local_reminder_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// Two systems were aiming at the same minute.
///
/// The phone schedules a 20:00 reminder locally, and the backend now sends its own at 20:00
/// in the learner's timezone. The server's is the better one — it is composed when it is
/// sent, so it can count the words actually due and stay quiet for somebody who already
/// practised — but the local one cannot simply be deleted: it is the only thing that still
/// works when push is unconfigured, undelivered, or switched off at the OS.
///
/// So the local schedule yields to evidence rather than to configuration, and takes the slot
/// back if the evidence goes stale.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = LocalReminderService();
  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleTextService.setAppLocale(const Locale('tr'));
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  List<MethodCall> callsNamed(String name) =>
      calls.where((call) => call.method == name).toList();

  test('with no server reminder in evidence, the local one is scheduled', () async {
    await service.scheduleDailyReminder();

    expect(callsNamed('zonedSchedule'), isNotEmpty,
        reason: 'standing down for a channel that has never delivered would leave '
            'the learner with no reminder at all');
  });

  test('once a server reminder actually arrives, the local one stands down', () async {
    await LocalReminderService.noteServerReminderDelivered();

    await service.scheduleDailyReminder();

    expect(callsNamed('zonedSchedule'), isEmpty);
    expect(callsNamed('cancel'), isNotEmpty,
        reason: 'the already-queued local reminder has to be withdrawn, not just '
            'left unscheduled next time');
  });

  test('if the server goes quiet, the local reminder takes the slot back', () async {
    // Four days: past the window in which one delivery is taken as proof.
    SharedPreferences.setMockInitialValues({
      'notifications:server_reminder_seen_at':
          DateTime.now().subtract(const Duration(days: 4)).toIso8601String(),
    });

    await service.scheduleDailyReminder();

    expect(callsNamed('zonedSchedule'), isNotEmpty,
        reason: 'a broken push pipeline must not mean permanent silence');
  });

  test('a corrupt timestamp is treated as no evidence, not as proof', () async {
    SharedPreferences.setMockInitialValues({
      'notifications:server_reminder_seen_at': 'not-a-date',
    });

    await service.scheduleDailyReminder();

    expect(callsNamed('zonedSchedule'), isNotEmpty);
  });

  test('a Turkish learner is not reminded in English', () async {
    // The old copy was one hardcoded English sentence, sent to people whose reason for
    // installing the app is that they do not read English comfortably yet.
    await service.scheduleDailyReminder();

    final scheduled = callsNamed('zonedSchedule').single;
    final args = Map<String, dynamic>.from(scheduled.arguments as Map);
    expect(args['body'], 'Bugünün pratiği seni bekliyor.');
  });

  test('an English learner still gets English', () async {
    LocaleTextService.setAppLocale(const Locale('en'));

    await service.scheduleDailyReminder();

    final scheduled = callsNamed('zonedSchedule').single;
    final args = Map<String, dynamic>.from(scheduled.arguments as Map);
    expect(args['body'], 'A quick practice session is ready for today.');
  });
}
