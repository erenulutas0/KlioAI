import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/screens/profile_page.dart';
import 'package:vocabmaster/services/push_token_service.dart';
import 'package:vocabmaster/services/support_ticket_service.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

class _FakeSupportTicketService extends SupportTicketService {
  String? lastType;
  String? lastTitle;
  String? lastMessage;
  String? lastLocale;
  int callCount = 0;
  Object? throwOnCreate;

  @override
  Future<Map<String, dynamic>> createTicket({
    required String type,
    required String title,
    required String message,
    required String locale,
  }) async {
    callCount += 1;
    lastType = type;
    lastTitle = title;
    lastMessage = message;
    lastLocale = locale;
    if (throwOnCreate != null) {
      throw throwOnCreate!;
    }
    return {
      'id': 99,
      'type': type,
      'title': title,
      'message': message,
      'status': 'OPEN',
      'remainingToday': 2,
      'dailyLimit': 3,
    };
  }
}

Future<void> _pumpProfilePage(
  WidgetTester tester,
  SupportTicketService supportTicketService,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});

  final themeProvider = ThemeProvider();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfilePage(
          // Avoid the real FirebaseMessaging.instance call PushTokenService's
          // default constructor makes; Firebase isn't initialized in widget tests.
          pushTokenService: PushTokenService(skipMessagingInstance: true),
          supportTicketService: supportTicketService,
          skipInitialRemoteLoads: true,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

// ProfilePage runs continuous background animations, so pumpAndSettle()
// never converges here; use bounded pumps instead (matches the existing
// profile_notification_preferences_flow_test.dart pattern).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Delete my account submits an ACCOUNT_DELETION support ticket after confirmation',
      (tester) async {
    final fakeService = _FakeSupportTicketService();
    await _pumpProfilePage(tester, fakeService);

    final deleteTile =
        find.byKey(const ValueKey('profile-delete-account-tile'));
    await tester.ensureVisible(deleteTile);
    await tester.tap(deleteTile);
    await _settle(tester);

    expect(find.text('Delete my account'), findsWidgets);
    expect(fakeService.callCount, 0,
        reason: 'tapping the tile should only open the confirmation dialog');

    await tester.tap(find.text('Request deletion'));
    await _settle(tester);

    expect(fakeService.callCount, 1);
    expect(fakeService.lastType, 'ACCOUNT_DELETION');
    expect(fakeService.lastLocale, 'en');
    expect(
      find.textContaining('deletion request has been received'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel does not submit a deletion request', (tester) async {
    final fakeService = _FakeSupportTicketService();
    await _pumpProfilePage(tester, fakeService);

    final deleteTile =
        find.byKey(const ValueKey('profile-delete-account-tile'));
    await tester.ensureVisible(deleteTile);
    await tester.tap(deleteTile);
    await _settle(tester);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    expect(fakeService.callCount, 0);
  });

  testWidgets('Shows the daily-limit message when the ticket quota is used up',
      (tester) async {
    final fakeService = _FakeSupportTicketService()
      ..throwOnCreate = SupportTicketException(
        statusCode: 429,
        message: 'daily ticket limit reached',
        payload: const {},
      );
    await _pumpProfilePage(tester, fakeService);

    final deleteTile =
        find.byKey(const ValueKey('profile-delete-account-tile'));
    await tester.ensureVisible(deleteTile);
    await tester.tap(deleteTile);
    await _settle(tester);

    await tester.tap(find.text('Request deletion'));
    await _settle(tester);

    expect(fakeService.callCount, 1);
    expect(
      find.textContaining('reached today\'s support request limit'),
      findsOneWidget,
    );
  });
}
