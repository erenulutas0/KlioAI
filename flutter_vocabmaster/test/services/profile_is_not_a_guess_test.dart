import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// What the app tells the server about a learner must be what the learner
/// said, not what their menus happen to be in.
///
/// Found on a phone while taking store screenshots. A word tapped in an
/// English book came back explained in Spanish — "gilded / Cubierto de oro" —
/// to a Turkish learner reading a Turkish interface. Settings showed
/// "Ana dil: İspanyolca" and the level had fallen from B2 to B1.
///
/// The app had been *viewed* in Spanish for ten minutes earlier that evening.
/// Nothing was stored for this learner (their onboarding answers predate the
/// fix in selectSourceLanguage), so every launch re-derived the profile from
/// the interface language, and currentProfile() sent that derivation to the
/// server as a fact. The server stores what it is sent, so the derivation
/// became the profile — and stayed after the interface went back to Turkish.
///
/// Two guards, because the bug needed both halves: the service must not claim
/// what nobody answered, and initialize() must not turn a fallback into an
/// answer on its way past.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LearningLanguageService.resetAnswers();
    LocaleTextService.setAppLocale(const Locale('en'));
  });

  tearDown(() {
    LearningLanguageService.resetAnswers();
    LocaleTextService.setAppLocale(const Locale('en'));
  });

  test('an unanswered profile sends nothing but the target language', () {
    final Map<String, String> profile = LearningLanguageService.currentProfile();

    expect(profile.containsKey('sourceLanguage'), isFalse,
        reason: 'nobody said this, so the server must keep what it has');
    expect(profile.containsKey('feedbackLanguage'), isFalse);
    expect(profile.containsKey('englishLevel'), isFalse);
    expect(profile.containsKey('learningGoal'), isFalse);
    // English is what this app teaches. It is not a guess about anyone.
    expect(profile['targetLanguage'], 'English');
  });

  test('the interface language cannot become an answer', () {
    // The exact ten minutes that corrupted the profile: the interface moves,
    // nothing is answered, and the request must stay silent about it.
    for (final String code in <String>['es', 'pt', 'it', 'fr', 'de', 'tr']) {
      LocaleTextService.setAppLocale(Locale(code));
      final Map<String, String> profile =
          LearningLanguageService.currentProfile();
      expect(profile.containsKey('sourceLanguage'), isFalse,
          reason: 'viewing the app in $code claimed a native language');
    }
  });

  test('an answer is sent, and is not the interface language', () {
    LearningLanguageService.setSourceLanguage('Turkish');
    LearningLanguageService.setEnglishLevel('B2');
    LocaleTextService.setAppLocale(const Locale('es'));

    final Map<String, String> profile = LearningLanguageService.currentProfile();
    expect(profile['sourceLanguage'], 'Turkish');
    expect(profile['feedbackLanguage'], 'Turkish');
    expect(profile['englishLevel'], 'B2');
  });

  test('initialize does not turn a fallback into an answer', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocaleTextService.setAppLocale(const Locale('es'));

    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();

    // The screens still get something to draw...
    expect(provider.sourceLanguage, 'Spanish');
    // ...and the server is still told nothing.
    expect(LearningLanguageService.currentProfile().containsKey('sourceLanguage'),
        isFalse,
        reason: 'initialize handed the service a guess, and the guess became '
            'the stored profile the moment any AI request was made');
  });

  test('initialize passes a real stored answer through', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'learning_source_language': 'Turkish',
      'learning_english_level': 'B2',
    });
    LocaleTextService.setAppLocale(const Locale('es'));

    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();

    expect(provider.sourceLanguage, 'Turkish');
    final Map<String, String> profile = LearningLanguageService.currentProfile();
    expect(profile['sourceLanguage'], 'Turkish');
    expect(profile['englishLevel'], 'B2');
  });
}
