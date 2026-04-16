
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_helper.dart';

// We need to test:
// 1. Streak updates (increment vs reset)
// 2. Daily Goal XP awards (once per day)

void main() {
  late AppStateProvider appState;
  late XPManager xpManager;
  final now = DateTime(2023, 1, 10, 12, 0); // Base date

  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    // Reset DB and Prefs
    await clearDatabase();
    SharedPreferences.setMockInitialValues({});
    
    xpManager = XPManager();
    XPManager.resetIdempotency();
    xpManager.invalidateCache();
    
    appState = AppStateProvider();
    
    // Set base mock date
    appState.mockDate = now;
    xpManager.mockDate = now;
  });

  tearDown(() {
    appState.mockDate = null;
    xpManager.mockDate = null;
  });

  group('Streak Logic Tests', () {
    test('First activity should start streak at 1', () async {
      await appState.incrementLearnedToday();
      
      expect(appState.userStats['streak'], 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('current_streak'), 1);
      expect(prefs.getString('last_activity_date'), '2023-01-10');
    });

    test('Activity on same day should valid existing streak', () async {
      // Day 1 Activity
      await appState.incrementLearnedToday();
      expect(appState.userStats['streak'], 1);
      
      // Another Activity same day
      await appState.incrementLearnedToday();
      expect(appState.userStats['streak'], 1, reason: 'Streak should not increase on same day');
    });

    test('Activity on next day should increment streak', () async {
      // Day 1
      await appState.incrementLearnedToday();
      expect(appState.userStats['streak'], 1);
      
      // Move to Day 2
      final tomorrow = now.add(const Duration(days: 1));
      appState.mockDate = tomorrow;
      xpManager.mockDate = tomorrow;
      
      // Day 2 Activity
      await appState.incrementLearnedToday();
      
      expect(appState.userStats['streak'], 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_activity_date'), '2023-01-11');
    });

    test('Missing a day should reset streak to 1', () async {
      // Day 1
      await appState.incrementLearnedToday();
      expect(appState.userStats['streak'], 1);
      
      // Move to Day 3 (Skipped Day 2)
      final day3 = now.add(const Duration(days: 2));
      appState.mockDate = day3;
      xpManager.mockDate = day3;
      
      // Day 3 Activity
      await appState.incrementLearnedToday();
      
      expect(appState.userStats['streak'], 1, reason: 'Streak should reset after missing a day');
    });
    
    test('Daily Goal XP awarded only once per day', () async {
      // Set Daily Goal to 1 for simplicity (default logic in test might check against userStats['dailyGoal'] ?? 5)
      // Let's assume default is 5. We can update it manually.
      appState.updateUserStats({'dailyGoal': 1});
      
      // 1. Complete Goal
      await appState.incrementLearnedToday(); // count = 1 >= 1
      await Future.delayed(Duration.zero); // Give time for _checkDailyGoal
      
      // Verify XP awarded
      // daily_goal is 25 XP
      int totalXP = await xpManager.getTotalXP();
      // incrementLearnedToday doesn't award XP by itself unless it triggers daily goal?
      // Wait, source code analysis:
      // incrementLearnedToday -> _updateStreak -> checkStreakBonus
      // incrementLearnedToday -> _checkDailyGoal -> checkDailyGoal
      // if satisfied -> addXP(dailyGoalComplete)
      
      // But addXPForAction gives XP for "dailyWord" etc if called directly.
      // `incrementLearnedToday` itself is just a counter.
      
      // So if goal is 1, and we called it, we *should* get 25 XP.
      expect(totalXP, 25);
      
      // 2. Do it again same day
      await appState.incrementLearnedToday();
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Should still be 25
      totalXP = await xpManager.getTotalXP();
      expect(totalXP, 25, reason: 'Daily Goal XP should be one-time only');
      
      // 3. Next Day
      final tomorrow = now.add(const Duration(days: 1));
      appState.mockDate = tomorrow;
      xpManager.mockDate = tomorrow;
      // Also need to reset "learnedToday" count for new day simulation?
      // The logic `AppStateProvider` doesn't automatically reset `learnedToday` in memory unless we re-init or have logic for it.
      // Let's check `_loadUserStats` or similar. In app, restart resets it or specific check.
      // But `incrementLearnedToday` reads from `_userStats['learnedToday']`.
      // If we don't reset it, it keeps increasing.
      // But `checkDailyGoal` logic in XPManager might handle "already awarded for TODAY".
      // Yes, `checkDailyGoal` calls `addXP(XPActionTypes.dailyGoalComplete)`.
      // `addXP` for dailyGoal checks `isRepeatable`. `dailyGoalComplete` is NOT repeatable.
      // `XPManager` verifies "repeatable" against key `xp_awarded_daily_goal_DATE`.
      
      // So even if `learnedToday` is high, `XPManager` checks date key.
      // Since date changed, key is new. So we should get XP again.
      
      await appState.incrementLearnedToday();
      await Future.delayed(Duration.zero);
      
      totalXP = await xpManager.getTotalXP();
      expect(totalXP, 50, reason: 'Daily Goal XP should be awarded again on next day');
    });
  });
}
