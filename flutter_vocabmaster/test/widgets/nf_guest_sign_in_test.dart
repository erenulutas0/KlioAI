import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/widgets/nf_guest_sign_in.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/auth_service.dart';

/// The offer that replaced the wall.
///
/// Signing in used to be the first screen in the app. It is now an offer made
/// after there is something to keep, and the whole point is that it stays an
/// offer: asked rarely, dropped after three refusals, and never asked of someone
/// who has already signed in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime start = DateTime(2026, 9, 19, 20);

  Future<void> beGuest() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AuthService().logout();
    await AuthService().saveSession('access', 'refresh', <String, dynamic>{
      'id': 7,
      'email': 'guest-xyz@guest.klioai.app',
      'displayName': 'Guest',
      'userTag': '#00007',
      'role': 'USER',
    }, guest: true);
  }

  test('a guest who has never been asked is asked', () async {
    await beGuest();

    expect(await NfGuestPromptSchedule.shouldAsk(now: start), isTrue);
  });

  test('and then not again the same evening', () async {
    await beGuest();
    await NfGuestPromptSchedule.recordAsked(now: start);

    expect(
        await NfGuestPromptSchedule.shouldAsk(
            now: start.add(const Duration(hours: 6))),
        isFalse);
    expect(
        await NfGuestPromptSchedule.shouldAsk(
            now: start.add(const Duration(hours: 21))),
        isTrue);
  });

  test('three refusals are an answer', () async {
    await beGuest();
    DateTime now = start;
    for (int i = 0; i < NfGuestPromptSchedule.maxAsks; i++) {
      await NfGuestPromptSchedule.recordAsked(now: now);
      now = now.add(const Duration(days: 1));
    }

    expect(await NfGuestPromptSchedule.shouldAsk(now: now), isFalse);
    expect(
        await NfGuestPromptSchedule.shouldAsk(
            now: now.add(const Duration(days: 365))),
        isFalse);
  });

  test('somebody who has signed in is never asked', () async {
    await beGuest();
    await AuthService().saveSession('access', 'refresh', <String, dynamic>{
      'id': 7,
      'email': 'real@example.com',
      'displayName': 'Eren',
      'userTag': '#00007',
      'role': 'USER',
    });

    expect(await NfGuestPromptSchedule.shouldAsk(now: start), isFalse);
  });

  // The sheet itself asks the session nothing -- NfGuestSignInSheet.maybeShow
  // does that before it is built -- so this one skips the session setup. It also
  // has to: AuthService.logout() makes a request, and a widget test's clock does
  // not run it.
  testWidgets('the sheet says what signing in keeps, and takes no for an answer',
      (WidgetTester tester) async {
    bool? result;

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
            onPressed: () async {
              result = await showModalBottomSheet<bool>(
                context: context,
                builder: (_) => const NfGuestSignInSheet(reason: 'test'),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(AppLocalizations(const Locale('tr')).t('guest.signIn.title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('guest-sign-in')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('guest-sign-in-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('guest-sign-in')), findsNothing);
    expect(result, isFalse);
  });
}
