import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/xp_manager.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

/// XP lived only on the device. The server had been recording its own total all
/// along — it awards for a new word, a new sentence and every graded review —
/// and the app had never read it, so reinstalling looked like losing progress:
/// the local ledger went with the uninstall and the app rebuilt a number from
/// the words it could still see. Everything that left nothing behind, which is
/// every review ever done, was gone.
///
/// The fix is a floor, not a takeover: the app keeps its own ledger and simply
/// refuses to sit below what the server knows.
void main() {
  setUpAll(setupTestEnv);

  setUp(() async {
    await clearDatabase();
    // XPManager keeps the total in SharedPreferences as well as the database,
    // and caches it in the instance. Without clearing both, one test's total
    // becomes the next test's floor and every assertion after the first passes
    // for the wrong reason.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    XPManager.resetIdempotency();
  });

  test('a reinstalled learner gets the server total back, not a guess',
      () async {
    // No words synced down yet, so the content estimate is 0 — exactly the
    // state a fresh install is in while it waits for its first sync.
    final provider = AppStateProvider();
    provider.setApiServiceForTesting(_StubApi(totalXp: 1240));

    await provider.refreshXpStatsFromLocal(notify: false);

    expect(provider.userStats['xp'], 1240);
  });

  test('a learner who is ahead of the server keeps their own number', () async {
    // The device counts things the server never sees — a finished translation
    // set, a streak bonus. Those must not be rounded away.
    final provider = AppStateProvider();
    provider.setApiServiceForTesting(_StubApi(totalXp: 100));

    await provider.refreshXpStatsFromLocal(notify: false);
    expect(provider.userStats['xp'], 100);

    await provider.addXPForAction(XPActionTypes.reviewComplete);
    final ahead = provider.userStats['xp'] as int;
    expect(ahead, greaterThan(100));

    // A later refresh must not pull it back down to the server's figure.
    await provider.refreshXpStatsFromLocal(notify: false);
    expect(provider.userStats['xp'], ahead);
  });

  test('an unreachable server changes nothing', () async {
    // Offline, or an older backend without the endpoint: the app behaves
    // exactly as it did before this existed.
    final provider = AppStateProvider();
    provider.setApiServiceForTesting(_StubApi.failing());

    await provider.refreshXpStatsFromLocal(notify: false);

    expect(provider.userStats['xp'], 0);
  });

  test('the server is asked once, not on every refresh', () async {
    // This runs on every tab change and after every award.
    final api = _StubApi(totalXp: 50);
    final provider = AppStateProvider();
    provider.setApiServiceForTesting(api);

    await provider.refreshXpStatsFromLocal(notify: false);
    await provider.refreshXpStatsFromLocal(notify: false);
    await provider.refreshXpStatsFromLocal(notify: false);

    expect(api.calls, 1);
  });
}

class _StubApi extends ApiService {
  _StubApi({required this.totalXp}) : fails = false;
  _StubApi.failing()
      : totalXp = 0,
        fails = true;

  final int totalXp;
  final bool fails;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getProgressStats() async {
    calls++;
    if (fails) {
      throw Exception('offline');
    }
    return <String, dynamic>{'totalXp': totalXp, 'level': 1};
  }
}
