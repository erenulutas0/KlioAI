import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_tutor_page.dart';
import 'package:vocabmaster/frontend_newest/theme/nf_theme_scope.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';

/// The opening line follows the interface language, on the screen.
///
/// The companion test beside this one only shows that the seven greetings
/// differ from each other, which was already true before the bug and after it.
/// This one changes the locale over a page that is already built and looks at
/// what it draws — which is the only thing that tells the two apart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('changing the language changes the greeting already on screen',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final LearningLanguageProvider learning = LearningLanguageProvider();
    await learning.initialize();

    Widget app(Locale locale) => MultiProvider(
          providers: [
            ChangeNotifierProvider<LearningLanguageProvider>.value(
                value: learning),
            ChangeNotifierProvider<NfFrontendPreference>(
                create: (_) => NfFrontendPreference()),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NfThemeScope(child: NfTutorPage()),
          ),
        );

    await tester.pumpWidget(app(const Locale('es')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final String spanish =
        AppLocalizations(const Locale('es')).t('tutor.greeting').split('{')[0];
    expect(find.textContaining(spanish), findsOneWidget,
        reason: 'the Spanish greeting never appeared, so the rest of this '
            'test would be checking nothing');

    // The same page, still alive, under a different language. This is the
    // shape the IndexedStack creates on a real phone: the tab is not rebuilt
    // from scratch when the language changes.
    await tester.pumpWidget(app(const Locale('tr')));
    await tester.pump();

    final String turkish =
        AppLocalizations(const Locale('tr')).t('tutor.greeting').split('{')[0];
    expect(find.textContaining(turkish), findsOneWidget,
        reason: 'the greeting stayed in Spanish under Turkish menus, which is '
            'exactly what was seen on the phone');
    expect(find.textContaining(spanish), findsNothing);
  });
}
