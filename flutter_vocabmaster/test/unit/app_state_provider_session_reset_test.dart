import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import '../test_helper.dart';

void main() {
  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await clearDatabase();
    XPManager.clearIdempotencyCache();
  });

  test('clearSessionState removes prior account in-memory data', () async {
    final appState = AppStateProvider();

    final word = await appState.addWord(
      english: 'switch',
      turkish: 'degistir',
      addedDate: DateTime(2026, 3, 21),
      difficulty: 'easy',
      source: 'manual',
    );

    expect(word, isNotNull);
    expect(appState.allWords, isNotEmpty);
    expect(appState.userStats['xp'], 10);

    appState.updateProfileImage(type: 'avatar', seed: 'old-user');
    appState.updateWeeklyActivity([
      {
        'day': 'Pzt',
        'count': 1,
        'learned': true,
      },
    ]);

    appState.clearSessionState();

    expect(appState.isInitialized, isFalse);
    expect(appState.userInfo, isNull);
    expect(appState.allWords, isEmpty);
    expect(appState.allSentences, isEmpty);
    expect(appState.userStats['xp'], 0);
    expect(appState.userStats['totalWords'], 0);
    expect(appState.userStats['streak'], 0);
    expect(appState.weeklyActivity, isEmpty);
    expect(appState.profileImageType, isNull);
    expect(appState.profileImagePath, isNull);
    expect(appState.avatarSeed, isEmpty);
  });
}
