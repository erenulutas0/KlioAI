import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

class AppTourService {
  static const String _completedKey = 'app_tour_completed_v2';

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    await AnalyticsService.logOnboardingCompleted();
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
  }
}
