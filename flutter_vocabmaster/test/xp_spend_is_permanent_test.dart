import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/xp_manager.dart';

/// XP has exactly one thing to spend it on — the streak freeze — and the purchase used to
/// refund itself.
///
/// ensureMinimumTotalXP re-derives a floor from the user's content (words x10,
/// sentences x5, ...) and lifts the total back up to it on every load. With no record of
/// spending, that floor treated a purchase as drift and put the XP straight back. A
/// learner with plenty of words got their streak freeze free; a learner with little
/// content actually paid. The only spend in the economy worked backwards, charging least
/// to whoever had earned most.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('nothing is spent to begin with', () async {
    expect(await XPManager().spentXp(), 0);
  });

  test('the floor is lowered by what has been spent', () async {
    // A user whose content earns a 2000 XP floor spends 500 on a streak freeze. The floor
    // that still applies to them is 1500 — the 500 is gone, not drifted.
    SharedPreferences.setMockInitialValues({'total_xp_spent': 500});

    final manager = XPManager();
    expect(await manager.spentXp(), 500);

    // A floor at or below what was spent must raise nothing at all.
    expect(await manager.ensureMinimumTotalXP(500), 0,
        reason: 'a floor fully covered by spending must not restore anything');
    expect(await manager.ensureMinimumTotalXP(300), 0);
  });

  test('spending accumulates across purchases', () async {
    SharedPreferences.setMockInitialValues({'total_xp_spent': 500});
    expect(await XPManager().spentXp(), 500);

    SharedPreferences.setMockInitialValues({'total_xp_spent': 1500});
    expect(await XPManager().spentXp(), 1500,
        reason: 'three streak freezes cost three times as much');
  });

  test('a zero or negative floor is still a no-op', () async {
    final manager = XPManager();
    expect(await manager.ensureMinimumTotalXP(0), 0);
    expect(await manager.ensureMinimumTotalXP(-100), 0);
  });
}
