import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/language_provider.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/screens/settings_page.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SettingsPage updates the learning source language',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    // Pinned rather than inherited from whichever machine runs this. The app
    // locale now decides what the learner's language defaults to before they
    // have chosen one, so leaving it to the platform made this test's subject
    // depend on the tester's own device.
    LocaleTextService.setAppLocale(const Locale('en'));

    final languageProvider = LanguageProvider();
    final learningProvider = LearningLanguageProvider();
    await languageProvider.initialize();
    await learningProvider.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: languageProvider),
          ChangeNotifierProvider.value(value: learningProvider),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Learning Profile'), findsOneWidget);
    // English, because nothing is stored and the interface is English.
    // Someone reading English menus is not asked to correct the app into
    // explaining things in English.
    expect(find.textContaining('Native language: English'), findsOneWidget);
    expect(find.textContaining('Practice language: English'), findsOneWidget);
    expect(find.textContaining('English level: B1'), findsOneWidget);
    expect(find.textContaining('Goal: Speaking'), findsOneWidget);

    expect(find.text('Select native language'), findsOneWidget);

    await learningProvider.selectSourceLanguage('Spanish');
    await learningProvider.selectEnglishLevel('B2');
    await learningProvider.selectLearningGoal('Travel');
    await tester.pump();

    expect(learningProvider.sourceLanguage, 'Spanish');
    expect(learningProvider.englishLevel, 'B2');
    expect(learningProvider.learningGoal, 'Travel');
    expect(LearningLanguageService.sourceLanguage, 'Spanish');
    expect(LearningLanguageService.englishLevel, 'B2');
    expect(LearningLanguageService.learningGoal, 'Travel');
    expect(find.textContaining('Native language: Spanish'), findsOneWidget);
    expect(find.textContaining('English level: B2'), findsOneWidget);
    expect(find.textContaining('Goal: Travel'), findsOneWidget);
  });
}
