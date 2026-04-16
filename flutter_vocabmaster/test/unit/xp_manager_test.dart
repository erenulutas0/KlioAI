import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import 'package:vocabmaster/services/local_database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_helper.dart';

void main() {
  late XPManager xpManager;

  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    // Reset SharedPreferences
    SharedPreferences.setMockInitialValues({});
    
    // Clear Database
    await clearDatabase();
    
    // Get fresh instance (singleton, but internal state should be clean effectively)
    xpManager = XPManager();

    // Force cache invalidation to re-read from (empty) DB/Prefs
    xpManager.invalidateCache();
    XPManager.resetIdempotency();
  });


  group('XPManager Logic Tests', () {
    test('Initial XP should be 0', () async {
      final totalXP = await xpManager.getTotalXP(forceRefresh: true);
      expect(totalXP, 0);
    });

    test('Adding Word XP (+10) updates total XP correctly', () async {
      // Action: Add Word XP
      final addedAmount = await xpManager.addXP(XPActionTypes.addWord);
      
      expect(addedAmount, 10);
      
      final totalXP = await xpManager.getTotalXP();
      expect(totalXP, 10);
    });

    test('XP history is recorded when XP is added', () async {
      await xpManager.addXP(XPActionTypes.addWord);
      final history = await LocalDatabaseService().getXpHistory(limit: 10);
      expect(history.isNotEmpty, true);
      expect(history.first['actionId'], 'add_word');
    });

    test('Daily Word XP is +10', () async {
      final addedAmount = await xpManager.addXP(XPActionTypes.dailyWordLearn);
      expect(addedAmount, 10);
      expect(await xpManager.getTotalXP(), 10);
    });

    test('Adding Sentence XP (+5) updates total XP correctly', () async {
      // Action: Add Sentence XP
      final addedAmount = await xpManager.addXP(XPActionTypes.addSentence);
      
      expect(addedAmount, 5);
      
      final totalXP = await xpManager.getTotalXP();
      expect(totalXP, 5);
    });

    test('Total XP accumulates correctly (Word + Sentence)', () async {
      await xpManager.addXP(XPActionTypes.addWord); // +10
      await xpManager.addXP(XPActionTypes.addSentence); // +5
      
      final totalXP = await xpManager.getTotalXP();
      expect(totalXP, 15);
    });

    test('Deducting XP works correctly', () async {
      // Setup: 20 XP
      await xpManager.addXP(XPActionTypes.addWord); // +10
      await xpManager.addXP(XPActionTypes.addWord); // +10
      expect(await xpManager.getTotalXP(), 20);

      // Action: Deduct 5 XP
      await xpManager.deductXP(5, 'Test Deduction');
      
      // Verify
      expect(await xpManager.getTotalXP(), 15);
    });

    test('XP cannot go below 0', () async {
      // Setup: 5 XP
      await xpManager.addXP(XPActionTypes.addSentence); // +5
      
      // Action: Deduct 10 XP
      await xpManager.deductXP(10, 'Overshoot Deduction');
      
      // Verify
      expect(await xpManager.getTotalXP(), 0);
    });

    test('Idempotency: Same transaction ID should not award XP twice', () async {
      const txId = 'unique_transaction_123';
      
      // First call
      final added1 = await xpManager.addXP(XPActionTypes.addWord, transactionId: txId);
      expect(added1, 10);
      expect(await xpManager.getTotalXP(), 10);
      
      // Second call with same ID
      final added2 = await xpManager.addXP(XPActionTypes.addWord, transactionId: txId);
      expect(added2, 0); // Should be 0
      expect(await xpManager.getTotalXP(), 10); // Should still be 10
    });

    test('Level Calculation checks', () {
      expect(xpManager.calculateLevel(0), 1);
      expect(xpManager.calculateLevel(99), 1);
      expect(xpManager.calculateLevel(100), 2);
      expect(xpManager.calculateLevel(249), 2);
      expect(xpManager.calculateLevel(250), 3);
    });
    
    test('Daily Streak Bonus logic', () async {
        // Mock daily logic if feasible, or just test the pure logic of the bonus simply
        // Here we can test if manually adding streak bonus works
        await xpManager.addXP(XPActionTypes.streakBonus3);
        expect(await xpManager.getTotalXP(), 15);
    });
  });
}
