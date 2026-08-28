import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_onboarding_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/language_provider.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/services/learning_language_service.dart';

/// The onboarding a learner actually reaches.
///
/// There is a second onboarding in this repo — `OnboardingScreen`, from the
/// retired design — and it has the profile step's test coverage, down to the
/// same widget keys. The app has not opened it since `main.dart` and the splash
/// screen started building [NfOnboardingPage] instead. So the tests passed, and
/// went on passing, while saying nothing whatsoever about the screen a first
/// run puts in front of someone.
///
/// This file drives the one that ships. The three questions are asked one at a
/// time now, so "all three answers are on screen at once" is no longer true and
/// no longer something to assert: what matters is that each question appears
/// once the one before it is answered, and that the answers reach the profile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LearningLanguageProvider learning;
  late LanguageProvider language;

  Future<void> openProfileStep(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    LearningLanguageService.setSourceLanguage('Turkish');
    LearningLanguageService.setEnglishLevel('B1');
    LearningLanguageService.setLearningGoal('Speaking');

    learning = LearningLanguageProvider();
    await learning.initialize();
    language = LanguageProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LearningLanguageProvider>.value(value: learning),
          ChangeNotifierProvider<LanguageProvider>.value(value: language),
          // NfThemeScope reads this to decide light or dark. Without it the
          // page cannot build at all, which is why the retired screen's tests
          // never needed it and this one does.
          ChangeNotifierProvider<NfFrontendPreference>(
              create: (_) => NfFrontendPreference()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NfOnboardingPage(
            fromSettings: true,
            initialPage: NfOnboardingPage.profilePageIndex,
            showLanguageStep: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder source(String value) => find.byKey(ValueKey<String>('onboarding-source-$value'));
  Finder level(String value) => find.byKey(ValueKey<String>('onboarding-level-$value'));
  Finder goal(String value) => find.byKey(ValueKey<String>('onboarding-goal-$value'));

  testWidgets('only the first question is asked to begin with',
      (WidgetTester tester) async {
    await openProfileStep(tester);

    expect(source('Spanish'), findsOneWidget);
    expect(level('B2'), findsNothing);
    expect(goal('Travel'), findsNothing);
  });

  testWidgets('each answer brings the next question', (WidgetTester tester) async {
    await openProfileStep(tester);

    await tester.tap(source('Spanish'));
    await tester.pumpAndSettle();
    expect(level('B2'), findsOneWidget);
    expect(goal('Travel'), findsNothing,
        reason: 'the third question should wait for the second answer');

    await tester.tap(level('B2'));
    await tester.pumpAndSettle();
    expect(goal('Travel'), findsOneWidget);
  });

  testWidgets('the answers reach the learning profile', (WidgetTester tester) async {
    await openProfileStep(tester);

    await tester.tap(source('Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(level('B2'));
    await tester.pumpAndSettle();
    await tester.tap(goal('Travel'));
    await tester.pumpAndSettle();

    expect(learning.sourceLanguage, 'Spanish');
    expect(learning.englishLevel, 'B2');
    expect(learning.learningGoal, 'Travel');
    expect(LearningLanguageService.sourceLanguage, 'Spanish');
    expect(LearningLanguageService.englishLevel, 'B2');
    expect(LearningLanguageService.learningGoal, 'Travel');
  });

  testWidgets('an answered question stays answerable', (WidgetTester tester) async {
    // Progressive reveal must not turn into a one-way street. Someone who
    // realises on the third question that they picked the wrong level has to be
    // able to reach back for it, not start the flow again.
    await openProfileStep(tester);

    await tester.tap(source('Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(level('B2'));
    await tester.pumpAndSettle();

    await tester.tap(level('C1'));
    await tester.pumpAndSettle();
    expect(learning.englishLevel, 'C1');
    expect(goal('Travel'), findsOneWidget,
        reason: 'changing an answer should not retract the questions after it');
  });

  testWidgets('the tutor says something back about the answer given',
      (WidgetTester tester) async {
    // The reason this is a conversation and not a progressive form. The reply
    // is chosen by the answer, so a wired-up-wrong version would show the same
    // line whatever you picked — these two must differ.
    await openProfileStep(tester);

    await tester.tap(source('Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(level('A1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('start gently'), findsOneWidget);

    await tester.tap(level('C1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('start gently'), findsNothing);
    expect(find.textContaining('stop simplifying'), findsOneWidget);
  });

  testWidgets('every goal has its own reply', (WidgetTester tester) async {
    // The reply key is built by interpolation — `onboarding.chat.goal.$goal` —
    // so the coverage test that reads literal `context.tr('...')` calls cannot
    // see any of them. Without this, adding a goal ships a screen that prints
    // "onboarding.chat.goal.Culture" at someone.
    await openProfileStep(tester);
    await tester.tap(source('Spanish'));
    await tester.pumpAndSettle();
    await tester.tap(level('B1'));
    await tester.pumpAndSettle();

    for (final String value in LearningLanguageService.supportedLearningGoals) {
      await tester.tap(goal(value));
      await tester.pumpAndSettle();
      expect(find.textContaining('onboarding.chat.goal.'), findsNothing,
          reason: '$value has no reply of its own');
    }
  });
}
