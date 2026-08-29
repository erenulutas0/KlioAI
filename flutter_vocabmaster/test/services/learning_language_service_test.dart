import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocaleTextService.setAppLocale(const Locale('en'));
    LearningLanguageService.setSourceLanguage(
      LearningLanguageService.defaultSourceLanguage,
    );
    LearningLanguageService.setEnglishLevel(
      LearningLanguageService.defaultEnglishLevel,
    );
    LearningLanguageService.setLearningGoal(
      LearningLanguageService.defaultLearningGoal,
    );
  });

  group('LearningLanguageService', () {
    test('normalizes supported source-language aliases', () {
      expect(
        LearningLanguageService.normalizeSupported('tr-TR', 'English'),
        'Turkish',
      );
      expect(
        LearningLanguageService.normalizeSupported('español', 'Turkish'),
        'Spanish',
      );
      expect(
        LearningLanguageService.normalizeSupported('pt-BR', 'Turkish'),
        'Portuguese',
      );
      expect(
        LearningLanguageService.normalizeSupported(
          'bahasa indonesia',
          'Turkish',
        ),
        'Indonesian',
      );
      expect(
        LearningLanguageService.normalizeSupported('Deutsch', 'Turkish'),
        'German',
      );
      expect(
        LearningLanguageService.normalizeSupported('français', 'Turkish'),
        'French',
      );
    });

    test('every interface language explains in that same language', () {
      // The default native language is derived from the interface, because
      // menus in one language and AI feedback in another is a strange thing to
      // hand someone to correct. It used to be derived by a switch listing tr
      // and de with everything else defaulting to English -- so the day four
      // locales were added, a Spanish reader silently got English
      // explanations, and nothing said so.
      //
      // Asked of the supported locales, not of a list typed in here: a locale
      // added later cannot slip past this by not being mentioned.
      final Map<String, String> derived = <String, String>{};
      for (final Locale locale in AppLocalizations.supportedLocales) {
        LocaleTextService.setAppLocale(locale);
        derived[locale.languageCode] =
            LearningLanguageService.defaultSourceLanguage;
      }
      LocaleTextService.setAppLocale(const Locale('en'));

      expect(derived.length, greaterThan(1),
          reason: 'one locale or none, so this measures nothing');

      for (final MapEntry<String, String> entry in derived.entries) {
        expect(
          LearningLanguageService.supportedSourceLanguages,
          contains(entry.value),
          reason: '${entry.key} derives "${entry.value}", which the profile '
              'picker does not offer',
        );
        if (entry.key != 'en') {
          expect(entry.value, isNot('English'),
              reason: '${entry.key} reads its menus in ${entry.key} and would '
                  'be explained to in English: add the language to '
                  'normalizeSupported');
        }
      }

      // Distinct, so two locales cannot quietly collapse onto one language.
      expect(derived.values.toSet().length, derived.length,
          reason: 'two interface languages share a native language: $derived');
    });

    test('falls back for unsupported profile values', () {
      LearningLanguageService.setSourceLanguage('Japanese');
      LearningLanguageService.setEnglishLevel('native');
      LearningLanguageService.setLearningGoal('gaming');

      expect(
        LearningLanguageService.sourceLanguage,
        LearningLanguageService.defaultSourceLanguage,
      );
      expect(
        LearningLanguageService.englishLevel,
        LearningLanguageService.defaultEnglishLevel,
      );
      expect(
        LearningLanguageService.learningGoal,
        LearningLanguageService.defaultLearningGoal,
      );
    });

    test('builds current AI profile from source language, level, and goal', () {
      LearningLanguageService.setSourceLanguage('es-MX');
      LearningLanguageService.setEnglishLevel('C1');
      LearningLanguageService.setLearningGoal('business');
      LocaleTextService.setAppLocale(const Locale('tr'));

      final profile = LearningLanguageService.currentProfile();

      expect(profile['sourceLanguage'], 'Spanish');
      expect(profile['targetLanguage'], 'English');
      // Spanish, not Turkish. This used to answer with the INTERFACE language,
      // so someone who had just told onboarding they speak Spanish was
      // explained to in Turkish because the menus were Turkish. The answer
      // they gave wins over the one inferred from their menus -- it is the
      // question onboarding asks, and the promise it makes when it asks.
      expect(profile['feedbackLanguage'], 'Spanish');
      expect(profile['englishLevel'], 'C1');
      expect(profile['learningGoal'], 'Work');
    });

    test('feedback reaches every language the server accepts', () {
      // Two of seven before this: Turkish if the interface was Turkish,
      // English otherwise. The server has always taken all seven
      // (LearningLanguageProfile.SUPPORTED_FEEDBACK_LANGUAGES) and was simply
      // never asked.
      for (final String language in LearningLanguageService.supportedSourceLanguages) {
        LearningLanguageService.setSourceLanguage(language);
        expect(LearningLanguageService.feedbackLanguage, language);
      }
    });

    test('before onboarding, the interface language stands in', () {
      // Someone reading German menus should not have to correct the app into
      // explaining things in German.
      LocaleTextService.setAppLocale(const Locale('de'));
      LearningLanguageService.setSourceLanguage('');
      expect(LearningLanguageService.feedbackLanguage, 'German');

      LocaleTextService.setAppLocale(const Locale('tr'));
      LearningLanguageService.setSourceLanguage('');
      expect(LearningLanguageService.feedbackLanguage, 'Turkish');
    });

    test('an interface language the app does not carry falls back to English', () {
      // Which is what the interface itself falls back to, so the two agree.
      LocaleTextService.setAppLocale(const Locale('fi'));
      LearningLanguageService.setSourceLanguage('');
      expect(LearningLanguageService.feedbackLanguage, 'English');
    });
  });
}
