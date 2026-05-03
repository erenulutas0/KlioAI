import 'package:shared_preferences/shared_preferences.dart';

class FirstSessionActivationService {
  static const selectedLevelKey = 'activation:selected_level';
  static const practiceCompletedKey = 'activation:practice_completed';
  static const dismissedKey = 'activation:dismissed';

  Future<String?> getSelectedLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final level = prefs.getString(selectedLevelKey);
    if (level == null || level.trim().isEmpty) {
      return null;
    }
    return level;
  }

  Future<void> setSelectedLevel(String level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(selectedLevelKey, level.trim().toUpperCase());
  }

  Future<bool> isPracticeCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(practiceCompletedKey) ?? false;
  }

  Future<void> markPracticeCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(practiceCompletedKey, true);
  }

  Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(dismissedKey) ?? false;
  }

  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(dismissedKey, true);
  }
}
