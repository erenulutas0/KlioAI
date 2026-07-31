import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/xp_manager.dart';

/// The level maths runs in two directions — XP to level, and level to the XP it starts at —
/// and they used to be two separately maintained ladders. Past the end of the table they
/// disagreed: calculateLevel counted 15000 XP as level 10 while xpForLevel said level 11
/// began there, so a user on 16000 XP was told the next level needed **-1000 XP** and their
/// progress bar sat at 100% forever. Only long-term users reached it.

void main() {
  final xp = XPManager();

  test('every level begins at the XP that maps back to it', () {
    // The invariant that makes the two directions one thing rather than two.
    for (var level = 1; level <= 40; level++) {
      expect(
        xp.calculateLevel(xp.xpForLevel(level)),
        level,
        reason: 'level $level starts at ${xp.xpForLevel(level)} XP, '
            'which must read back as level $level',
      );
    }
  });

  test('one XP below a threshold is still the previous level', () {
    for (var level = 2; level <= 40; level++) {
      expect(
        xp.calculateLevel(xp.xpForLevel(level) - 1),
        level - 1,
        reason: 'the last XP before level $level belongs to level ${level - 1}',
      );
    }
  });

  test('the XP still needed for the next level is never negative', () {
    // This is what the user actually saw. Walk across the end of the table, where the two
    // ladders used to part company.
    for (var totalXp = 0; totalXp <= 60000; totalXp += 250) {
      final level = xp.calculateLevel(totalXp);
      final needed = xp.xpForLevel(level + 1) - totalXp;
      expect(needed, greaterThan(0),
          reason: 'at $totalXp XP (level $level) the next level appeared '
              '$needed XP away');
    }
  });

  test('the early levels keep their published thresholds', () {
    // Changing the curve is a product decision; this pins it so a refactor cannot move it
    // by accident.
    expect(xp.calculateLevel(0), 1);
    expect(xp.calculateLevel(99), 1);
    expect(xp.calculateLevel(100), 2);
    expect(xp.calculateLevel(250), 3);
    expect(xp.calculateLevel(11000), 10);
    expect(xp.calculateLevel(14999), 10);
    expect(xp.calculateLevel(15000), 11);
  });

  test('levels past the table cost a flat 5000 XP each', () {
    expect(xp.xpForLevel(11), 15000);
    expect(xp.xpForLevel(12), 20000);
    expect(xp.xpForLevel(13), 25000);
    expect(xp.calculateLevel(20000), 12);
    expect(xp.calculateLevel(24999), 12);
  });
}
