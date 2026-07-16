import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/screens/onboarding_screen.dart';
import 'package:vocabmaster/services/app_tour_service.dart';
import 'package:vocabmaster/services/learning_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding profile step persists selected learning profile',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    LearningLanguageService.setSourceLanguage('Turkish');
    LearningLanguageService.setEnglishLevel('B1');
    LearningLanguageService.setLearningGoal('Speaking');

    final learningProvider = LearningLanguageProvider();
    await learningProvider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: learningProvider,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(fromSettings: true, initialPage: 4),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('onboarding-source-Spanish')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-level-B2')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('onboarding-goal-Travel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-source-Spanish')));
    await tester.tap(find.byKey(const ValueKey('onboarding-level-B2')));
    await tester.tap(find.byKey(const ValueKey('onboarding-goal-Travel')));
    await tester.pump();

    expect(learningProvider.sourceLanguage, 'Spanish');
    expect(learningProvider.englishLevel, 'B2');
    expect(learningProvider.learningGoal, 'Travel');
    expect(LearningLanguageService.sourceLanguage, 'Spanish');
    expect(LearningLanguageService.englishLevel, 'B2');
    expect(LearningLanguageService.learningGoal, 'Travel');

    await tester.tap(find.byKey(const ValueKey('onboarding-start-button')));
    await tester.pump();

    expect(await AppTourService().isCompleted(), true);
  });

  testWidgets(
      'third onboarding slide promotes daily words/review, not disabled social features',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final learningProvider = LearningLanguageProvider();
    await learningProvider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: learningProvider,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(fromSettings: true, initialPage: 2),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Daily Words & Smart Review'), findsOneWidget);
    expect(find.text('Spaced Repetition'), findsOneWidget);
    // The old slide advertised community features that are disabled in prod
    // (with a fabricated "5000+ Users" stat); it must stay gone.
    expect(find.text('Social Learning Platform'), findsNothing);
    expect(find.textContaining('5000+'), findsNothing);

    // Drain the slide's staggered feature-text animation timers (up to 800ms
    // Future.delayed) so the test binding's pending-timer invariant passes.
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('first-run onboarding finishes by navigating to LoginPage',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    LearningLanguageService.setSourceLanguage('Turkish');
    LearningLanguageService.setEnglishLevel('B1');
    LearningLanguageService.setLearningGoal('Speaking');

    final learningProvider = LearningLanguageProvider();
    await learningProvider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: learningProvider,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(
            initialPage: 4,
            loginPageBuilder: (_) => const Scaffold(
              body: Text('login-target'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('onboarding-source-Spanish')));
    await tester.tap(find.byKey(const ValueKey('onboarding-level-B2')));
    await tester.tap(find.byKey(const ValueKey('onboarding-goal-Travel')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('onboarding-start-button')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(await AppTourService().isCompleted(), true);
    expect(learningProvider.sourceLanguage, 'Spanish');
    expect(learningProvider.englishLevel, 'B2');
    expect(learningProvider.learningGoal, 'Travel');
    expect(find.text('login-target'), findsOneWidget);
  });
}
