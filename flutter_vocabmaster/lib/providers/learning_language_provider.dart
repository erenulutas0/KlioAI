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
    _sourceLanguage = LearningLanguageService.normalizeSupported(
      prefs.getString(_sourceLanguageKey) ?? '',
      LearningLanguageService.defaultSourceLanguage,
    );
    _englishLevel = LearningLanguageService.normalizeEnglishLevel(
      prefs.getString(_englishLevelKey) ?? '',
    );
    _learningGoal = LearningLanguageService.normalizeLearningGoal(
      prefs.getString(_learningGoalKey) ?? '',
    );
    LearningLanguageService.setSourceLanguage(_sourceLanguage);
    LearningLanguageService.setEnglishLevel(_englishLevel);
    LearningLanguageService.setLearningGoal(_learningGoal);
    _initialized = true;
    notifyListeners();
  }

  Future<void> selectSourceLanguage(String language) async {
    final normalized = LearningLanguageService.normalizeSupported(
      language,
      LearningLanguageService.defaultSourceLanguage,
    );
    if (_sourceLanguage == normalized) {
      return;
    }

    _sourceLanguage = normalized;
    LearningLanguageService.setSourceLanguage(_sourceLanguage);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceLanguageKey, _sourceLanguage);
  }

  Future<void> selectEnglishLevel(String level) async {
    final normalized = LearningLanguageService.normalizeEnglishLevel(level);
    if (_englishLevel == normalized) {
      return;
    }

    _englishLevel = normalized;
    LearningLanguageService.setEnglishLevel(_englishLevel);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_englishLevelKey, _englishLevel);
  }

  Future<void> selectLearningGoal(String goal) async {
    final normalized = LearningLanguageService.normalizeLearningGoal(goal);
    if (_learningGoal == normalized) {
      return;
    }

    _learningGoal = normalized;
    LearningLanguageService.setLearningGoal(_learningGoal);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learningGoalKey, _learningGoal);
  }
}
