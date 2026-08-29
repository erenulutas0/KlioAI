import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/providers/learning_language_provider.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// The learner's own language, and whether the app remembers being told it.
///
/// The default used to be the constant 'Turkish', so a choice that matched it
/// could go unwritten forever and nobody would know: re-deriving it on the next
/// launch produced the same answer every time. Then the default started
/// following the interface language — better for a German user opening the app
/// for the first time, and a trap for everyone else, because an answer that was
/// never stored now drifts when the interface changes.
///
/// Every test here is the same scenario at a different point: a Turkish learner
/// who said they speak Turkish, then switched the app to English.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The service holds its answers in statics, so one test's answer used to
    // leak into the next. It never showed, because initialize() overwrote them
    // unconditionally -- which is the very thing that turned a guess into a
    // stored profile on a real phone. Now that it only passes on what was
    // actually stored, the leak is visible and has to be cleared here.
    LearningLanguageService.resetAnswers();
    LocaleTextService.setAppLocale(const Locale('tr'));
  });

  test('confirming the default is still an answer, and is stored', () async {
    // The exact path onboarding takes. In Turkish the chip a Turkish speaker
    // taps is already what the default returned, so the write is the only thing
    // standing between them and a language they never chose.
    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();
    expect(provider.sourceLanguage, 'Turkish');

    await provider.selectSourceLanguage('Turkish');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('learning_source_language'), 'Turkish');
  });

  test('the stored answer survives a change of interface language', () async {
    // The failure this guards. Before the fix nothing was written above, the
    // next launch re-derived the default from the new interface language, and
    // a Turkish speaker was told they speak English: their AI feedback stopped
    // arriving in Turkish and translation practice offered them English to
    // English.
    final LearningLanguageProvider first = LearningLanguageProvider();
    await first.initialize();
    await first.selectSourceLanguage('Turkish');

    LocaleTextService.setAppLocale(const Locale('en'));

    final LearningLanguageProvider afterRestart = LearningLanguageProvider();
    await afterRestart.initialize();

    expect(afterRestart.sourceLanguage, 'Turkish');
    expect(LearningLanguageService.feedbackLanguage, 'Turkish');
  });

  test('a learner who has never answered still follows the interface', () async {
    // The reason the default was made to move in the first place. Nothing
    // stored, German menus: German, without making them correct the app.
    LocaleTextService.setAppLocale(const Locale('de'));

    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();

    expect(provider.sourceLanguage, 'German');
    expect(LearningLanguageService.feedbackLanguage, 'German');
  });

  test('level and goal are remembered the same way', () async {
    // Their defaults are constants, so an unwritten answer cannot drift today.
    // That is a property of a value somewhere else, and the one above stopped
    // being true the moment that value changed.
    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();

    await provider.selectEnglishLevel(provider.englishLevel);
    await provider.selectLearningGoal(provider.learningGoal);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('learning_english_level'), isNotNull);
    expect(prefs.getString('learning_goal'), isNotNull);
  });

  test('changing the answer still changes it', () async {
    final LearningLanguageProvider provider = LearningLanguageProvider();
    await provider.initialize();

    await provider.selectSourceLanguage('German');

    expect(provider.sourceLanguage, 'German');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('learning_source_language'), 'German');
  });
}
