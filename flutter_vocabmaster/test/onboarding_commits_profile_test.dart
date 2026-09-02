import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// Finishing onboarding has to count as an answer, even when the learner
/// changed nothing.
///
/// `hasAnswered` exists to stop a guess being sent to the server as a fact —
/// the app displays a native language derived from the interface language, and
/// merely viewing the menus in Spanish for ten minutes must not rewrite a
/// Turkish learner's stored profile. That is right, and it left a hole.
///
/// A learner who tapped Skip and then Start learning answered nothing, so
/// `currentProfile()` omitted `sourceLanguage`, so the server filled the gap
/// from the row it creates at signup — which is Turkish. A Spanish or German
/// user arriving from a link got every meaning, correction and explanation in
/// Turkish, while Settings showed them "Spanish", because Settings reads the
/// local guess and the server had never been told.
///
/// The fix is not to weaken `hasAnswered`. It is that onboarding commits what
/// is on screen when it closes, which is what the provider's own `select*`
/// methods were already written to do ("confirming the default IS an answer").
/// These tests hold that property from the service side, where it is testable
/// without pumping a five-page PageView.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LearningLanguageService.resetAnswers();
  });

  test('a fresh install has answered nothing', () {
    expect(LearningLanguageService.hasAnswered, isFalse);
    expect(LearningLanguageService.currentProfile().containsKey('sourceLanguage'),
        isFalse,
        reason: 'an unanswered guess must not be sent as an answer');
  });

  test('confirming the defaults counts, and reaches the server payload',
      () async {
    // What onboarding now does at _finish(): write back whatever is displayed.
    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();
    await provider.selectSourceLanguage(provider.sourceLanguage);
    await provider.selectEnglishLevel(provider.englishLevel);
    await provider.selectLearningGoal(provider.learningGoal);

    expect(LearningLanguageService.hasAnswered, isTrue);

    final Map<String, String> sent = LearningLanguageService.currentProfile();
    expect(sent['sourceLanguage'], isNotNull,
        reason: 'without this the server applies its own Turkish default');
    expect(sent['englishLevel'], isNotNull);
    expect(sent['learningGoal'], isNotNull);
    expect(sent['targetLanguage'], 'English');
  });

  test('the committed language follows the device, not Turkish', () async {
    // The defect in one line: a Spanish phone must not end up telling the
    // server nothing and being answered in Turkish.
    for (final String code in <String>['es', 'de', 'fr', 'it', 'pt', 'en']) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      LearningLanguageService.resetAnswers();
      LocaleTextService.setAppLocale(Locale(code));

      final LearningLanguageProvider provider = LearningLanguageProvider();
      await provider.initialize();
      await provider.selectSourceLanguage(provider.sourceLanguage);

      expect(LearningLanguageService.currentProfile()['sourceLanguage'],
          isNot('Turkish'),
          reason: 'a $code device committed Turkish as its native language');
    }
  });

  test('a real answer still wins over the default', () async {
    // The guard must not be so eager that it overwrites a choice. A Turkish
    // learner reading the app in English stays Turkish.
    LocaleTextService.setAppLocale(const Locale('en'));
    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();
    await provider.selectSourceLanguage('Turkish');

    expect(provider.sourceLanguage, 'Turkish');
    expect(LearningLanguageService.currentProfile()['sourceLanguage'],
        'Turkish');
  });
}
