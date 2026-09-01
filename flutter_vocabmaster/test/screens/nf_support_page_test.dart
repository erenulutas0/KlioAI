import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_support_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/support_ticket_service.dart';

/// The support form, and the reasons it is shaped the way it is.
///
/// The ticket service was written long before this screen and had no door.
/// The only routes to it were a report control beside a sentence mid-exercise
/// and a sheet the app opens by itself after a third practice — both about
/// content. Somebody charged twice, locked out, or asking for their data to be
/// deleted had nowhere at all to go, and Play requires a route for the last of
/// those. So the tests that matter here are about the door staying open: the
/// deletion type reaching the server under the name the server knows, and the
/// email surviving as the one path that works when the form cannot.
class _RecordingService implements SupportTicketService {
  _RecordingService({this.throws = false});

  final bool throws;
  final List<Map<String, String?>> sent = <Map<String, String?>>[];

  @override
  Future<Map<String, dynamic>> createTicket({
    required String type,
    required String title,
    required String message,
    required String locale,
    Map<String, dynamic>? context,
  }) async {
    if (throws) {
      throw StateError('missing-auth-context');
    }
    sent.add(<String, String?>{
      'type': type,
      'title': title,
      'message': message,
      'locale': locale,
    });
    return <String, dynamic>{'id': 1};
  }

  @override
  Future<Map<String, dynamic>> listTickets() async => <String, dynamic>{};
}

void main() {
  Widget host(SupportTicketService service, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: NfSupportPage(service: service),
    );
  }

  testWidgets('a message reaches the service under the chosen type',
      (WidgetTester tester) async {
    final _RecordingService service = _RecordingService();
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'I was charged twice');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.sent, hasLength(1));
    expect(service.sent.single['message'], 'I was charged twice');
    expect(service.sent.single['type'], 'BUG', reason: 'the default type');
    expect(service.sent.single['locale'], 'en');
  });

  testWidgets('account deletion is offered and goes over as ACCOUNT_DELETION',
      (WidgetTester tester) async {
    // The name matters as much as the route: the server's TicketType enum is
    // what decides whether this lands in the queue somebody actually watches.
    final _RecordingService service = _RecordingService();
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete my account'));
    await tester.pump();

    // Choosing it says what it costs, before anything is sent.
    expect(find.textContaining('permanent'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Please delete my account');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.sent.single['type'], 'ACCOUNT_DELETION');
  });

  testWidgets('an empty message cannot be sent', (WidgetTester tester) async {
    final _RecordingService service = _RecordingService();
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.sent, isEmpty);

    // Whitespace is empty too.
    await tester.enterText(find.byType(TextField), '   \n  ');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.sent, isEmpty);
  });

  testWidgets('a failure says so and keeps what was written',
      (WidgetTester tester) async {
    // This is the signed-out case: createTicket throws missing-auth-context,
    // and the person it throws for is the one who cannot log in. Losing their
    // message as well would be the second insult.
    await tester.pumpWidget(host(_RecordingService(throws: true)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Cannot log in');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not send'), findsOneWidget);
    expect(find.text('Cannot log in'), findsOneWidget,
        reason: 'the message was cleared on a failure, so it is gone');
  });

  testWidgets('the email is on screen whatever happens',
      (WidgetTester tester) async {
    // The form needs an account; the address does not. It is the only route
    // that works for someone locked out, so it is not behind an error state.
    await tester.pumpWidget(host(_RecordingService(throws: true)));
    await tester.pumpAndSettle();
    expect(find.text(NfSupportPage.email), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text(NfSupportPage.email), findsOneWidget);
  });

  test('every string this screen draws exists in every language', () {
    const List<String> keys = <String>[
      'settings.support',
      'support.title',
      'support.subtitle',
      'support.type.bug',
      'support.type.complaint',
      'support.type.request',
      'support.type.deletion',
      'support.message.hint',
      'support.send',
      'support.sent',
      'support.error',
      'support.email.label',
      'support.deletion.note',
    ];

    final List<String> missing = <String>[];
    for (final Locale locale in AppLocalizations.supportedLocales) {
      for (final String key in keys) {
        // `t` returns the key when there is no value, which on this screen
        // would draw "support.type.bug" on a chip.
        if (AppLocalizations(locale).t(key) == key) {
          missing.add('  ${locale.languageCode}: $key');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'These would render as their own key names:\n'
            '${missing.join('\n')}');
  });
}
