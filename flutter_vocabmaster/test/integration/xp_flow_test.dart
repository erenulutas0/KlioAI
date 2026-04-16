import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_helper.dart';

void main() {
  late AppStateProvider appState;
  late XPManager xpManager;

  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    // Reset SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Clear Database
    await clearDatabase();

    // Reset Services
    xpManager = XPManager();
    xpManager.invalidateCache();
    XPManager.resetIdempotency();

    // Initialize Provider
    appState = AppStateProvider();
    // We intentionally don't call full initialize() to avoid Network calls if possible,
    // or we mock the network parts.
    // Ideally we'd mock OfflineSyncService, but since we are doing integration
    // and using real SQLite, let's use the real service but mocked network via "Offline" mode?
    // The OfflineSyncService tries to check connectivity.
    // For this test, we can rely on Local logic primarily.
  });

  group('AppState Integration Flow (Word/Sentence/XP)', () {
    test('Adding a word increases XP by 10', () async {
      // 1. Add Word
      final addedWord = await appState.addWord(
        english: 'Apple',
        turkish: 'Elma',
        addedDate: DateTime.now(),
        difficulty: 'easy',
        source: 'manual',
      );

      expect(addedWord, isNotNull);

      // 2. Check XP
      final totalXP = await xpManager.getTotalXP(forceRefresh: true);
      expect(totalXP, 10, reason: 'Creating a word should give 10 XP');

      // 3. Verify User Stats in Provider match
      expect(appState.userStats['xp'], 10);
    });

    test('Adding a sentence to a word increases XP by 5', () async {
      // 1. Add Word (+10 XP)
      final word = await appState.addWord(
        english: 'Banana',
        turkish: 'Muz',
        addedDate: DateTime.now(),
        difficulty: 'medium',
      );
      expect(word, isNotNull);

      // 2. Add Sentence (+5 XP)
      await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'I like bananas.',
        translation: 'Muzları severim.',
        difficulty: 'easy',
      );

      // 3. Check XP (10 + 5 = 15)
      final totalXP = await xpManager.getTotalXP(forceRefresh: true);
      expect(totalXP, 15, reason: 'Word + Sentence should equal 15 XP');
    });

    test('Deleting a word removes XP for word AND its sentences', () async {
      // 1. Add Word (+10)
      final word = await appState.addWord(
        english: 'Car',
        turkish: 'Araba',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );

      // 2. Add Sentence (+5)
      await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'The car is red.',
        translation: 'Araba kırmızıdır.',
      );

      // XP check before delete
      expect(await xpManager.getTotalXP(forceRefresh: true), 15);

      // 3. Delete Word
      // This should trigger deduction of 10 (word) + 5 (sentence) = 15
      final deleted = await appState.deleteWord(word.id);
      expect(deleted, isTrue);

      // 4. Verify XP is 0
      final totalXP = await xpManager.getTotalXP(forceRefresh: true);
      expect(totalXP, 0,
          reason: 'Deleting word with sentence should revert all XP');
    });

    test('Add multiple sentences and verify XP logic', () async {
      final word = await appState.addWord(
        english: 'Run',
        turkish: 'Koşmak',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );
      // Base XP: 10

      await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'I run fast.',
        translation: 'Hızlı koşarım.',
      );
      // XP: 15

      await appState.addSentenceToWord(
        wordId: word.id,
        sentence: 'He runs slow.',
        translation: 'O yavaş koşar.',
      );
      // XP: 20

      expect(await xpManager.getTotalXP(forceRefresh: true), 20);
    });

    test('Deleting just a sentence updates XP correctly', () async {
      // 1. Setup Word + Sentence
      final word = await appState.addWord(
        english: 'Cat',
        turkish: 'Kedi',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      ); // +10

      final updatedWord = await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'Meow',
        translation: 'Miyav',
      ); // +5

      // Ensure we get the correct sentence ID
      final sentenceId = updatedWord!.sentences.last.id;

      expect(await xpManager.getTotalXP(), 15);

      // 2. Delete Sentence
      final deleted = await appState.deleteSentenceFromWord(
          wordId: word.id, sentenceId: sentenceId);
      expect(deleted, isTrue);

      // 3. Verify XP (Should drop by 5)
      final totalXP = await xpManager.getTotalXP(forceRefresh: true);
      expect(totalXP, 10, reason: 'Deleting sentence should deduct 5 XP');
    });

    test('Adding practice sentence (independent) gives 5 XP', () async {
      // 1. Add Practice Sentence
      await appState.addPracticeSentence(
          englishSentence: 'Hello World',
          turkishTranslation: 'Merhaba Dünya',
          difficulty: 'easy');

      // 2. Verify XP
      final totalXP = await xpManager.getTotalXP(forceRefresh: true);
      expect(totalXP, 5);

      // 3. Delete Practice Sentence
      // We need the ID. Since we didn't capture it easily from the void/bool method above (wait, it returns bool/object?),
      // let's peek at the list.
      final sentences =
          appState.allSentences.where((s) => s.isPractice).toList();
      expect(sentences.isNotEmpty, true);
      final id = sentences.first.id;

      final deleted = await appState.deletePracticeSentence(id);
      expect(deleted, isTrue);

      // 4. Verify XP deducted
      expect(await xpManager.getTotalXP(forceRefresh: true), 0);
    });

    test('Offline mode keeps words and sentences accessible after refresh',
        () async {
      final word = await appState.addWord(
        english: 'OfflineCheck',
        turkish: 'CevrimdisiKontrol',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      ); // +10

      expect(word, isNotNull);

      await appState.addSentenceToWord(
        wordId: word!.id,
        sentence: 'Offline sentence',
        translation: 'Cevrimdisi cumle',
        difficulty: 'easy',
      ); // +5

      await appState.addPracticeSentence(
        englishSentence: 'Practice offline sentence',
        turkishTranslation: 'Pratik cevrimdisi cumle',
        difficulty: 'easy',
      ); // +5

      expect(await xpManager.getTotalXP(forceRefresh: true), 20);

      await appState.refreshWords();
      await appState.refreshSentences();

      final hasWord =
          appState.allWords.any((w) => w.englishWord == 'OfflineCheck');
      final hasWordSentence = appState.allSentences.any(
        (s) => !s.isPractice && s.sentence == 'Offline sentence',
      );
      final hasPracticeSentence = appState.allSentences.any(
        (s) => s.isPractice && s.sentence == 'Practice offline sentence',
      );

      expect(hasWord, isTrue);
      expect(hasWordSentence, isTrue);
      expect(hasPracticeSentence, isTrue);
    });

    test('Deleting missing sentence does not change XP', () async {
      final word = await appState.addWord(
        english: 'Stable',
        turkish: 'Stabil',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );
      expect(word, isNotNull);
      expect(await xpManager.getTotalXP(forceRefresh: true), 10);

      final deleted = await appState.deleteSentenceFromWord(
        wordId: word!.id,
        sentenceId: 999999,
      );
      expect(deleted, isFalse);
      expect(
        await xpManager.getTotalXP(forceRefresh: true),
        10,
        reason: 'Failed delete must not deduct XP',
      );
    });

    test('Deleting same word twice keeps XP non-negative', () async {
      final word = await appState.addWord(
        english: 'Once',
        turkish: 'Bir kez',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );
      expect(word, isNotNull);
      expect(await xpManager.getTotalXP(forceRefresh: true), 10);

      final firstDelete = await appState.deleteWord(word!.id);
      final secondDelete = await appState.deleteWord(word.id);

      expect(firstDelete, isTrue);
      expect(secondDelete, isFalse);
      expect(await xpManager.getTotalXP(forceRefresh: true), 0);
      expect((appState.userStats['weeklyXP'] as int?) ?? 0,
          greaterThanOrEqualTo(0));
    });
  });
}
