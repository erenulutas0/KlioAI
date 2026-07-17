import 'locale_text_service.dart';

class LearningLanguageService {
  const LearningLanguageService._();

  static const String defaultSourceLanguage = 'Turkish';
  static const String targetLanguage = 'English';
  static const List<String> supportedSourceLanguages = [
    'Turkish',
    'English',
    'Spanish',
    'Portuguese',
    'Indonesian',
    'German',
    'French',
  ];
  static const String defaultEnglishLevel = 'B1';
  static const List<String> supportedEnglishLevels = [
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];

  static const String defaultLearningGoal = 'Speaking';
  static const List<String> supportedLearningGoals = [
    'Speaking',
    'Vocabulary',
    'Exam',
    'Work',
    'Travel',
  ];

  static String _sourceLanguage = defaultSourceLanguage;
  static String _englishLevel = defaultEnglishLevel;
  static String _learningGoal = defaultLearningGoal;

  static String get sourceLanguage => _sourceLanguage;
  static String get englishLevel => _englishLevel;
  static String get learningGoal => _learningGoal;
  static String get feedbackLanguage =>
      LocaleTextService.isTurkish ? 'Turkish' : 'English';

  static void setSourceLanguage(String language) {
    _sourceLanguage = normalizeSupported(language, defaultSourceLanguage);
  }

  static void setEnglishLevel(String level) {
    _englishLevel = normalizeEnglishLevel(level);
  }

  static void setLearningGoal(String goal) {
    _learningGoal = normalizeLearningGoal(goal);
  }

  static Map<String, String> currentProfile() {
    return {
      'sourceLanguage': _sourceLanguage,
      'targetLanguage': targetLanguage,
      'feedbackLanguage': feedbackLanguage,
      'englishLevel': _englishLevel,
      'learningGoal': _learningGoal,
    };
  }

  static String normalizeSupported(String value, String fallback) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'tr' || 'tr-tr' || 'turkish' || 'turkce' || 'türkçe' => 'Turkish',
      'en' || 'en-us' || 'en-gb' || 'english' => 'English',
      'es' ||
      'es-es' ||
      'es-mx' ||
      'spanish' ||
      'espanol' ||
      'español' =>
        'Spanish',
      'pt' ||
      'pt-br' ||
      'pt-pt' ||
      'portuguese' ||
      'portugues' ||
      'português' =>
        'Portuguese',
      'id' || 'id-id' || 'indonesian' || 'bahasa indonesia' => 'Indonesian',
      'de' || 'de-de' || 'german' || 'deutsch' => 'German',
      'fr' || 'fr-fr' || 'french' || 'francais' || 'français' => 'French',
      _ => fallback,
    };
  }

  static String normalizeEnglishLevel(String value) {
    final normalized = value.trim().toUpperCase();
    return supportedEnglishLevels.contains(normalized)
        ? normalized
        : defaultEnglishLevel;
  }

  static String normalizeLearningGoal(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'speaking' ||
      'speak' ||
      'conversation' ||
      'konusma' ||
      'konuşma' =>
        'Speaking',
      'vocabulary' || 'words' || 'kelime' || 'kelimeler' => 'Vocabulary',
      'exam' || 'ielts' || 'toefl' || 'yds' || 'sinav' || 'sınav' => 'Exam',
      'work' || 'career' || 'business' || 'is' || 'iş' => 'Work',
      'travel' || 'trip' || 'seyahat' || 'gezi' => 'Travel',
      _ => defaultLearningGoal,
    };
  }
}
