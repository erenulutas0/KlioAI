import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/local_database_service.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import '../test_helper.dart';

void main() {
  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await clearDatabase();
    XPManager.resetIdempotency();
  });

  group('AppStateProvider XP Integration', () {
    test('Adding a manual word awards +10 XP and updates user stats', () async {
      final appState = AppStateProvider();

      final word = await appState.addWord(
        english: 'test',
        turkish: 'test',
        addedDate: DateTime(2026, 2, 9),
        difficulty: 'easy',
        source: 'manual',
      );

      expect(word, isNotNull);
      expect(appState.userStats['xp'], 10);
    });

    test('Daily word add gives +10 XP, plus sentence gives +5 XP (total 15)',
        () async {
      final appState = AppStateProvider();

      final word = await appState.addWord(
        english: 'daily',
        turkish: 'günün kelimesi',
        addedDate: DateTime(2026, 2, 9),
        difficulty: 'medium',
        source: 'daily_word',
      );

      expect(word, isNotNull);
      expect(appState.userStats['xp'], 10);

      await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'This is a daily word.',
        translation: 'Bu bir günün kelimesidir.',
        difficulty: 'medium',
      );

      expect(appState.userStats['xp'], 15);
    });

    test('Word and sentence actions keep weekly XP current before refresh',
        () async {
      final appState = AppStateProvider();

      final word = await appState.addWord(
        english: 'instant',
        turkish: 'anlik',
        addedDate: DateTime.now(),
        difficulty: 'easy',
        source: 'manual',
      );

      expect(word, isNotNull);
      expect(appState.userStats['xp'], 10);
      expect(appState.userStats['weeklyXP'], 10);
      expect(appState.userStats['xpToNextLevel'], 90);

      await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'Instant feedback keeps the app feeling alive.',
        translation: 'Anlik geri bildirim uygulamayi canli hissettirir.',
        difficulty: 'easy',
      );

      expect(appState.userStats['xp'], 15);
      expect(appState.userStats['weeklyXP'], 15);
      expect(appState.userStats['xpToNextLevel'], 85);

      appState.updateUserStats({'weeklyXP': 0});
      expect(appState.userStats['weeklyXP'], 0);

      await appState.refreshXpStatsFromLocal();

      expect(appState.userStats['xp'], 15);
      expect(appState.userStats['weeklyXP'], 15);
      expect(appState.userStats['xpToNextLevel'], 85);
    });

    test('Custom XP updates weekly XP only once', () async {
      final appState = AppStateProvider();

      final added = await appState.addXP(10, reason: 'Perfect reading bonus');

      expect(added, 10);
      expect(appState.userStats['xp'], 10);
      expect(appState.userStats['weeklyXP'], 10);
    });

    test('XP callback tolerates persisted numeric strings in user stats',
        () async {
      final appState = AppStateProvider();

      appState.updateUserStats({
        'xp': '0',
        'weeklyXP': '40',
        'level': '1',
        'xpToNextLevel': '100',
      });

      expect(appState.userStats['xp'], 0);
      expect(appState.userStats['weeklyXP'], 40);
      expect(appState.userStats['level'], 1);
      expect(appState.userStats['xpToNextLevel'], 100);

      final added = await appState.addXPForAction(
        XPActionTypes.addWord,
        source: 'manual',
        transactionId: 'numeric-string-stats-refresh',
      );

      expect(added, 10);
      expect(appState.userStats['xp'], 10);
      expect(appState.userStats['weeklyXP'], 10);
      expect(appState.userStats['xpToNextLevel'], 90);
    });

    test('Action XP refreshes total and weekly stats immediately', () async {
      final appState = AppStateProvider();

      final added = await appState.addXPForAction(
        XPActionTypes.addWord,
        source: 'manual',
        transactionId: 'word-live-refresh-1',
      );

      expect(added, 10);
      expect(appState.userStats['xp'], 10);
      expect(appState.userStats['weeklyXP'], 10);
      expect(appState.userStats['xpToNextLevel'], 90);
    });

    test('XP refresh restores weekly XP from local learning content', () async {
      final localDb = LocalDatabaseService();
      await localDb.createWordOffline(
        english: 'weekly',
        turkish: 'haftalik',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );

      final appState = AppStateProvider();
      await appState.initialize();
      final prefs = await SharedPreferences.getInstance();
      final todayKey = 'xp_${DateTime.now().toIso8601String().split('T')[0]}';
      await prefs.setInt(todayKey, 0);
      appState.updateUserStats({'weeklyXP': 0});

      await appState.refreshXpStatsFromLocal();

      expect(appState.userStats['weeklyXP'], 10);
    });
  });
}
