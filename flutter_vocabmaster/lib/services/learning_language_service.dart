import 'package:flutter/foundation.dart';

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
  ///
  /// Asked of [normalizeSupported] rather than a switch of its own. The switch
  /// that stood here listed tr and de and defaulted everything else to
  /// English, so the day Spanish, Portuguese, Italian and French were added,
  /// each of them read its menus in one language and had the AI explain in
  /// another -- the exact thing the paragraph above says not to do. The
  /// normalizer already knows every code the picker can produce, and a test
  /// holds it to that.
  static String get defaultSourceLanguage =>
      normalizeSupported(LocaleTextService.appLanguageCode, 'English');
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
  static String? _englishLevelOverride;
  static String? _learningGoalOverride;

  static String get sourceLanguage =>
      _sourceLanguageOverride ?? defaultSourceLanguage;
  static String get englishLevel => _englishLevelOverride ?? defaultEnglishLevel;
  static String get learningGoal => _learningGoalOverride ?? defaultLearningGoal;

  /// Whether the learner has actually answered, as opposed to being shown a
  /// guess made from the language their menus happen to be in.
  ///
  /// The difference is the whole of [currentProfile]. Guessing is right for
  /// what to display before onboarding; sending the guess to the server as if
  /// it were an answer is how a Turkish learner's stored profile became
  /// Spanish and their level dropped from B2 to B1 after the app had merely
  /// been *viewed* in Spanish for ten minutes.
  static bool get hasAnswered =>
      _sourceLanguageOverride != null ||
      _englishLevelOverride != null ||
      _learningGoalOverride != null;
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
    _englishLevelOverride = normalizeEnglishLevel(level);
  }

  static void setLearningGoal(String goal) {
    _learningGoalOverride = normalizeLearningGoal(goal);
  }

  /// Forgets every answer, so the getters fall back to the guesses again.
  /// Only tests need this; the app has no way to un-answer.
  @visibleForTesting
  static void resetAnswers() {
    _sourceLanguageOverride = null;
    _englishLevelOverride = null;
    _learningGoalOverride = null;
  }

  /// What to tell the server about this learner.
  ///
  /// Only what they have answered. The server stores whatever it is sent and
  /// serves the AI from it, so a field included here is a claim about the
  /// learner, not a hint -- and a guess made from the interface language is
  /// not a claim anyone made.
  ///
  /// This used to send all five unconditionally, filling the unanswered ones
  /// from the defaults. Those defaults follow the interface language, so ten
  /// minutes of viewing the app in Spanish rewrote a Turkish learner's stored
  /// profile to Spanish and their level from B2 down to B1 -- the default --
  /// and every AI answer afterwards came back in Spanish, including the
  /// meaning of a word tapped in an English book. Nothing on screen said so:
  /// the settings page reads the provider, which had cached the old values.
  ///
  /// The server already treats an absent field as "keep what you have"
  /// (ChatbotController.languageProfileFrom), so omitting is both safe and the
  /// honest thing to send.
  static Map<String, String> currentProfile() {
    return <String, String>{
      if (_sourceLanguageOverride != null) ...<String, String>{
        'sourceLanguage': sourceLanguage,
        'feedbackLanguage': feedbackLanguage,
      },
      // Never a guess: English is what this app teaches, in every profile.
      'targetLanguage': targetLanguage,
      if (_englishLevelOverride != null) 'englishLevel': englishLevel,
      if (_learningGoalOverride != null) 'learningGoal': learningGoal,
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
