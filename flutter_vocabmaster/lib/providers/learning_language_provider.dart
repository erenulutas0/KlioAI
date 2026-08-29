import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/learning_language_service.dart';

class LearningLanguageProvider extends ChangeNotifier {
  static const String _sourceLanguageKey = 'learning_source_language';
  static const String _englishLevelKey = 'learning_english_level';
  static const String _learningGoalKey = 'learning_goal';

  String _sourceLanguage = LearningLanguageService.defaultSourceLanguage;
  String _englishLevel = LearningLanguageService.defaultEnglishLevel;
  String _learningGoal = LearningLanguageService.defaultLearningGoal;
  bool _initialized = false;

  String get sourceLanguage => _sourceLanguage;
  String get targetLanguage => LearningLanguageService.targetLanguage;
  String get englishLevel => _englishLevel;
  String get learningGoal => _learningGoal;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedSource = prefs.getString(_sourceLanguageKey);
    final String? storedLevel = prefs.getString(_englishLevelKey);
    final String? storedGoal = prefs.getString(_learningGoalKey);

    _sourceLanguage = LearningLanguageService.normalizeSupported(
      storedSource ?? '',
      LearningLanguageService.defaultSourceLanguage,
    );
    _englishLevel = LearningLanguageService.normalizeEnglishLevel(
      storedLevel ?? '',
    );
    _learningGoal = LearningLanguageService.normalizeLearningGoal(
      storedGoal ?? '',
    );

    // Only what is actually stored is handed to the service. The three fields
    // above still fall back to a guess so the screens have something to draw,
    // but the service is what the API sends, and it must be able to tell an
    // answer from a guess: an unanswered field is left absent so the server
    // keeps whatever it holds.
    //
    // Passing all three unconditionally is what let a Turkish learner's stored
    // profile become Spanish. Nothing was stored for them -- their onboarding
    // answers predate the fix in selectSourceLanguage below -- so every launch
    // re-derived the profile from the interface language and sent it as fact.
    if (storedSource != null && storedSource.isNotEmpty) {
      LearningLanguageService.setSourceLanguage(_sourceLanguage);
    }
    if (storedLevel != null && storedLevel.isNotEmpty) {
      LearningLanguageService.setEnglishLevel(_englishLevel);
    }
    if (storedGoal != null && storedGoal.isNotEmpty) {
      LearningLanguageService.setLearningGoal(_learningGoal);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> selectSourceLanguage(String language) async {
    final normalized = LearningLanguageService.normalizeSupported(
      language,
      LearningLanguageService.defaultSourceLanguage,
    );
    // The write happens even when the answer matches what is already held.
    // Confirming the default IS an answer, and it has to be stored as one.
    //
    // This early return used to be harmless: the default was the constant
    // 'Turkish', so re-deriving it on the next launch produced the same value
    // forever. Now that the default follows the interface language, an
    // unrecorded choice drifts with it — a Turkish learner who taps "Türkçe"
    // in onboarding stores nothing, and after switching the interface to
    // English their native language silently becomes English on the next cold
    // start. Their AI feedback stops arriving in Turkish, and translation
    // practice asks them to translate English into English.
    if (_sourceLanguage != normalized) {
      _sourceLanguage = normalized;
      LearningLanguageService.setSourceLanguage(_sourceLanguage);
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceLanguageKey, _sourceLanguage);
  }

  Future<void> selectEnglishLevel(String level) async {
    final normalized = LearningLanguageService.normalizeEnglishLevel(level);
    // Same shape as selectSourceLanguage above, for the same reason. These two
    // defaults are still constants, so an unrecorded answer cannot drift yet —
    // but "cannot drift yet" is a property of a value somewhere else, and the
    // one above stopped being true the moment that value changed.
    if (_englishLevel != normalized) {
      _englishLevel = normalized;
      LearningLanguageService.setEnglishLevel(_englishLevel);
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_englishLevelKey, _englishLevel);
  }

  Future<void> selectLearningGoal(String goal) async {
    final normalized = LearningLanguageService.normalizeLearningGoal(goal);
    // Same shape as selectSourceLanguage above, for the same reason. These two
    // defaults are still constants, so an unrecorded answer cannot drift yet —
    // but "cannot drift yet" is a property of a value somewhere else, and the
    // one above stopped being true the moment that value changed.
    if (_learningGoal != normalized) {
      _learningGoal = normalized;
      LearningLanguageService.setLearningGoal(_learningGoal);
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learningGoalKey, _learningGoal);
  }
}
