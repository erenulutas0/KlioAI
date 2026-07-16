import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
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
      expect(profile['feedbackLanguage'], 'Turkish');
      expect(profile['englishLevel'], 'C1');
      expect(profile['learningGoal'], 'Work');
    });
  });
}
