import 'locale_text_service.dart';

class LearningLanguageService {
  const LearningLanguageService._();

  /// The learner's own language before they have told us, taken from the
  /// interface they are already reading.
  ///
  /// It was the constant 'Turkish', which is right for most of this app's
  /// audience and wrong in the one case that matters: someone using the app in
  /// German got German menus and German-language AI feedback was never even
  /// offered to the server. A default that contradicts the language on screen
  /// is a strange thing to make someone correct by hand.
  ///
  /// English rather than Turkish for anything else, because that is what the
  /// interface itself falls back to.
  static String get defaultSourceLanguage => switch (LocaleTextService.appLanguageCode) {
        'tr' => 'Turkish',
        'de' => 'German',
        _ => 'English',
      };
  static const String targetLanguage = 'English';
  static const List<String> supportedSourceLanguages = [
    'Turkish',
    'English',
    'Spanish',
    'Portuguese',
    'Indonesian',
    'German',
    'French',
    'Italian',
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

  // Not initialised from the getter: a static initialiser would freeze
  // whatever the locale was at class-load time, which on a cold start is
  // before the app has read the stored language.
  static String? _sourceLanguageOverride;
  static String _englishLevel = defaultEnglishLevel;
  static String _learningGoal = defaultLearningGoal;

  static String get sourceLanguage =>
      _sourceLanguageOverride ?? defaultSourceLanguage;
  static String get englishLevel => _englishLevel;
  static String get learningGoal => _learningGoal;
  /// The language the AI explains and corrects in.
  ///
  /// The learner's own language, which is exactly what onboarding asks for and
  /// what it promises: "meanings and corrections arrive in this language".
  ///
  /// It used to be a single boolean -- Turkish if the interface was Turkish,
  /// English otherwise -- so of the seven languages the server accepts
  /// (LearningLanguageProfile.SUPPORTED_FEEDBACK_LANGUAGES) the app could ask
  /// for two. A learner who told us they speak German, Spanish or Portuguese
  /// was answered in English anyway, by a server that would have obliged.
  ///
  /// The two lists are the same seven, which is not a coincidence to rely on
  /// quietly: a source language the server does not accept comes back as its
  /// own fallback there rather than breaking anything here.
  static String get feedbackLanguage => sourceLanguage;

  static void setSourceLanguage(String language) {
    _sourceLanguageOverride = normalizeSupported(language, defaultSourceLanguage);
  }

  static void setEnglishLevel(String level) {
    _englishLevel = normalizeEnglishLevel(level);
  }

  static void setLearningGoal(String goal) {
    _learningGoal = normalizeLearningGoal(goal);
  }

  static Map<String, String> currentProfile() {
    return {
      'sourceLanguage': sourceLanguage,
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
      'it' || 'it-it' || 'italian' || 'italiano' => 'Italian',
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
