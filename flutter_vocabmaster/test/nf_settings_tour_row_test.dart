import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_onboarding_page.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_settings_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/language_provider.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';

/// The way back to the tour.
///
/// NfOnboardingPage is constructed in exactly two places — main.dart and the
/// splash screen — and both are behind gates that fire once ever. After a first
/// run there was no route to it at all, while the strings for a replay row sat
/// finished in all three languages waiting for something to render them.
///
/// The retired settings screen did have such a button, which is how this went
/// unnoticed: the feature existed, just not in the half of the app that ships.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> showSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});

    final LearningLanguageProvider learning = LearningLanguageProvider();
    await learning.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningLanguageProvider>.value(value: learning),
          ChangeNotifierProvider<LanguageProvider>(create: (_) => LanguageProvider()),
          ChangeNotifierProvider<NfFrontendPreference>(
              create: (_) => NfFrontendPreference()),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NfSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final Finder row = find.byKey(const ValueKey<String>('settings-replay-tour'));

  testWidgets('settings offers a way to see the tour again',
      (WidgetTester tester) async {
    await showSettings(tester);
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);
  });

  testWidgets('and it opens the onboarding the app actually ships',
      (WidgetTester tester) async {
    // Named on purpose. The retired settings screen pushes the retired
    // OnboardingScreen, and a replay that reached the old form instead of the
    // conversation would look completely fine from the outside.
    await showSettings(tester);
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(NfOnboardingPage), findsOneWidget);
  });

  testWidgets('the row is labelled a tour, not a species',
      (WidgetTester tester) async {
    // "tür" is a kind or a type; "tur" is a tour. The Turkish label read
    // "Türü tekrar oynat" — replay the species — and no spelling rule in this
    // repo could object, because both are real words. Pinned here because the
    // guards structurally cannot catch it.
    await showSettings(tester);
    await tester.scrollUntilVisible(row, 200);

    expect(find.text('Turu tekrar izle'), findsOneWidget);
    expect(find.textContaining('Türü'), findsNothing);
  });
}
