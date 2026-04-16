import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/models/sentence_practice.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/local_database_service.dart';
import 'package:vocabmaster/services/offline_sync_service.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import '../test_helper.dart';

class ToggleConnectivity implements Connectivity {
  ToggleConnectivity(this.online);

  bool online;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return [online ? ConnectivityResult.wifi : ConnectivityResult.none];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  Future<void> deleteService() async {}

  Future<String?> getWifiBSSID() async => null;

  Future<String?> getWifiIP() async => null;

  Future<String?> getWifiName() async => null;
}

class FakeSyncApiService extends ApiService {
  int _wordSeq = 2000;
  int _sentenceSeq = 9000;
  int _practiceSeq = 7000;
  final Map<int, Word> _serverWords = {};
  final Map<String, SentencePractice> _serverPracticeSentences = {};

  @override
  Future<List<Word>> getAllWords() async {
    return _serverWords.values.toList();
  }

  @override
  Future<Word> getWordById(int id) async {
    final word = _serverWords[id];
    if (word == null) {
      throw Exception('Word not found');
    }
    return word;
  }

  @override
  Future<List<SentencePractice>> getAllSentences() async {
    final all = <SentencePractice>[];

    // Practice sentences (server table)
    all.addAll(_serverPracticeSentences.values);

    // Word sentences (combined /sentences endpoint behavior)
    for (final word in _serverWords.values) {
      for (final s in word.sentences) {
        all.add(SentencePractice(
          id: 'word_${s.id}',
          englishSentence: s.sentence,
          turkishTranslation: s.translation,
          difficulty: (s.difficulty ?? 'easy').toLowerCase(),
          createdDate: word.learnedDate,
          source: 'word',
          word: word.englishWord,
          wordTranslation: word.turkishMeaning,
        ));
      }
    }

    return all;
  }

  @override
  Future<Word> createWord({
    required String english,
    required String turkish,
    required DateTime addedDate,
    String difficulty = 'easy',
  }) async {
    final id = ++_wordSeq;
    final word = Word(
      id: id,
      englishWord: english,
      turkishMeaning: turkish,
      learnedDate: addedDate,
      difficulty: difficulty,
      notes: '',
      sentences: const [],
    );
    _serverWords[id] = word;
    return word;
  }

  @override
  Future<Word> addSentenceToWord({
    required int wordId,
    required String sentence,
    required String translation,
    String difficulty = 'easy',
  }) async {
    final existing = _serverWords[wordId] ??
        Word(
          id: wordId,
          englishWord: 'unknown_$wordId',
          turkishMeaning: '',
          learnedDate: DateTime.now(),
          difficulty: 'easy',
          notes: '',
          sentences: const [],
        );

    // Backend-like idempotency: same sentence + translation should not create duplicates.
    final alreadyExists = existing.sentences.any((s) =>
        s.sentence.trim() == sentence.trim() &&
        s.translation.trim() == translation.trim());
    if (alreadyExists) {
      return existing;
    }

    final newSentence = Sentence(
      id: ++_sentenceSeq,
      sentence: sentence,
      translation: translation,
      wordId: wordId,
      difficulty: difficulty,
    );
    final updated = Word(
      id: existing.id,
      englishWord: existing.englishWord,
      turkishMeaning: existing.turkishMeaning,
      learnedDate: existing.learnedDate,
      difficulty: existing.difficulty,
      notes: existing.notes,
      sentences: [...existing.sentences, newSentence],
    );
    _serverWords[wordId] = updated;
    return updated;
  }

  @override
  Future<SentencePractice> createSentence({
    required String englishSentence,
    required String turkishTranslation,
    required String difficulty,
  }) async {
    final created = SentencePractice(
      id: 'practice_${++_practiceSeq}',
      englishSentence: englishSentence,
      turkishTranslation: turkishTranslation,
      difficulty: difficulty.toUpperCase(),
      createdDate: DateTime.now(),
      source: 'practice',
    );
    _serverPracticeSentences[created.id] = created;
    return created;
  }

  @override
  Future<void> deleteSentence(String id) async {
    final key = id.startsWith('practice_') ? id : 'practice_$id';
    _serverPracticeSentences.remove(key);
  }

  @override
  Future<void> deleteSentenceFromWord(int wordId, int sentenceId) async {
    final existing = _serverWords[wordId];
    if (existing == null) return;
    final updated = Word(
      id: existing.id,
      englishWord: existing.englishWord,
      turkishMeaning: existing.turkishMeaning,
      learnedDate: existing.learnedDate,
      difficulty: existing.difficulty,
      notes: existing.notes,
      sentences: existing.sentences.where((s) => s.id != sentenceId).toList(),
    );
    _serverWords[wordId] = updated;
  }

  @override
  Future<void> deleteWord(int id) async {
    _serverWords.remove(id);
  }

  void seedServerWord(Word word) {
    _serverWords[word.id] = word;
    if (word.id > _wordSeq) {
      _wordSeq = word.id;
    }
    for (final sentence in word.sentences) {
      if (sentence.id > _sentenceSeq) {
        _sentenceSeq = sentence.id;
      }
    }
  }
}

class NoOpDeleteSyncApiService extends FakeSyncApiService {
  @override
  Future<void> deleteSentenceFromWord(int wordId, int sentenceId) async {
    // Simulate backend mismatch behavior where delete responds but sentence remains.
  }
}

void main() {
  late OfflineSyncService syncService;
  late ToggleConnectivity connectivity;
  late AppStateProvider appState;
  late XPManager xpManager;

  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await clearDatabase();
    XPManager.resetIdempotency();

    await AuthService().saveSession('test_token', 'test_refresh', {
      'id': 4,
      'userId': 4,
      'email': 'smoke@test.local',
      'displayName': 'Smoke Test',
      'userTag': '#00004',
      'role': 'USER',
    });

    connectivity = ToggleConnectivity(false);
    syncService = OfflineSyncService();
    syncService.setDependenciesForTesting(
      apiService: FakeSyncApiService(),
      connectivity: connectivity,
    );
    syncService.resetStatusForTesting();

    xpManager = XPManager();
    xpManager.invalidateCache();

    appState = AppStateProvider();
  });

  test('Offline to online smoke flow preserves data and XP', () async {
    final newWord = await appState.addWord(
      english: 'Airplane',
      turkish: 'Ucak',
      addedDate: DateTime.now(),
      difficulty: 'easy',
      source: 'manual',
    );
    expect(newWord, isNotNull);
    expect(newWord!.id, lessThan(0),
        reason: 'Offline word should use local id');

    final updatedWord = await appState.addSentenceToWord(
      wordId: newWord.id,
      sentence: 'I am learning English on the airplane.',
      translation: 'Ucakta İngilizce calisiyorum.',
      difficulty: 'medium',
    );
    expect(updatedWord, isNotNull);

    final practiceAdded = await appState.addPracticeSentence(
      englishSentence: 'Offline practice sentence',
      turkishTranslation: 'Offline pratik cumlesi',
      difficulty: 'easy',
    );
    expect(practiceAdded, isTrue);

    final xpBeforeSync = await xpManager.getTotalXP(forceRefresh: true);
    expect(xpBeforeSync, 20,
        reason: 'Word(10)+WordSentence(5)+PracticeSentence(5)');

    final localDb = LocalDatabaseService();
    final queueBefore = await localDb.getPendingSyncItems();
    expect(
      queueBefore.where((q) => q['action'] == 'create').length,
      3,
      reason: 'Offline queue should include word+sentence+practice sentence',
    );

    connectivity.online = true;
    syncService.resetStatusForTesting();
    await syncService.syncPendingChanges();

    final queueAfter = await localDb.getPendingSyncItems();
    expect(queueAfter, isEmpty,
        reason: 'All pending create actions should sync');

    final wordsAfterSync = await localDb.getAllWords();
    expect(wordsAfterSync.length, 1);
    expect(wordsAfterSync.first.id, greaterThan(0));
    expect(wordsAfterSync.first.englishWord, 'Airplane');
    expect(wordsAfterSync.first.sentences.length, 1);
    expect(wordsAfterSync.first.sentences.first.id, greaterThan(0));

    final practiceAfterSync = await localDb.getAllPracticeSentences();
    expect(practiceAfterSync.length, 1);
    expect(practiceAfterSync.first.id.startsWith('practice_'), isTrue);

    await appState.refreshWords();
    await appState.refreshSentences();

    expect(
      appState.allWords.any((w) => w.englishWord == 'Airplane'),
      isTrue,
    );
    expect(
      appState.allSentences.any((s) =>
          !s.isPractice &&
          s.sentence == 'I am learning English on the airplane.'),
      isTrue,
    );
    expect(
      appState.allSentences.any(
          (s) => s.isPractice && s.sentence == 'Offline practice sentence'),
      isTrue,
    );

    final xpAfterSync = await xpManager.getTotalXP(forceRefresh: true);
    expect(xpAfterSync, 20, reason: 'Sync should not alter already earned XP');
    expect(appState.userStats['xp'], 20);
  });

  test(
      'Offline delete smoke: deletions sync cleanly and XP never goes negative',
      () async {
    final word = await appState.addWord(
      english: 'DeleteFlow',
      turkish: 'SilmeAkisi',
      addedDate: DateTime.now(),
      difficulty: 'easy',
      source: 'manual',
    );
    expect(word, isNotNull);

    final withSentence = await appState.addSentenceToWord(
      wordId: word!.id,
      sentence: 'Delete this sentence offline.',
      translation: 'Bu cumleyi offline sil.',
      difficulty: 'easy',
    );
    expect(withSentence, isNotNull);
    expect(withSentence!.sentences, isNotEmpty);

    final practiceAdded = await appState.addPracticeSentence(
      englishSentence: 'Delete this practice sentence offline.',
      turkishTranslation: 'Bu pratik cumleyi offline sil.',
      difficulty: 'easy',
    );
    expect(practiceAdded, isTrue);
    expect(await xpManager.getTotalXP(forceRefresh: true), 20);

    final sentenceId = withSentence.sentences.last.id;
    final sentenceDeleted = await appState.deleteSentenceFromWord(
      wordId: word.id,
      sentenceId: sentenceId,
    );
    expect(sentenceDeleted, isTrue);
    expect(await xpManager.getTotalXP(forceRefresh: true), 15);

    final practice = appState.allSentences.firstWhere((s) => s.isPractice);
    final practiceDeleted = await appState.deletePracticeSentence(practice.id);
    expect(practiceDeleted, isTrue);
    expect(await xpManager.getTotalXP(forceRefresh: true), 10);

    final wordDeleted = await appState.deleteWord(word.id);
    expect(wordDeleted, isTrue);
    expect(await xpManager.getTotalXP(forceRefresh: true), 0);

    final secondDelete = await appState.deleteWord(word.id);
    expect(secondDelete, isFalse);
    expect(await xpManager.getTotalXP(forceRefresh: true), 0);

    final localDb = LocalDatabaseService();
    final queueBeforeSync = await localDb.getPendingSyncItems();
    expect(
      queueBeforeSync.where((q) => q['status'] == 'pending'),
      isEmpty,
      reason:
          'Create/delete queue items should be cleaned for local-only deletes',
    );

    connectivity.online = true;
    syncService.resetStatusForTesting();
    await syncService.syncPendingChanges();

    expect(await localDb.getAllWords(), isEmpty);
    expect(await localDb.getAllPracticeSentences(), isEmpty);

    await appState.refreshWords();
    await appState.refreshSentences();
    expect(appState.allWords, isEmpty);
    expect(appState.allSentences, isEmpty);
    expect(await xpManager.getTotalXP(forceRefresh: true), 0);
    expect(
        (appState.userStats['weeklyXP'] as int?) ?? 0, greaterThanOrEqualTo(0));
  });

  test(
      'Offline duplicate sentence rows are cleaned after sync and XP is not double-deducted',
      () async {
    final word = await appState.addWord(
      english: 'Prioritize',
      turkish: 'Oncelik ver',
      addedDate: DateTime.now(),
      difficulty: 'easy',
      source: 'manual',
    );
    expect(word, isNotNull);

    const sentence = 'I need to prioritize my study plan this week.';
    const translation = 'Bu hafta calisma planima oncelik vermem gerekiyor.';

    final withSentence1 = await appState.addSentenceToWord(
      wordId: word!.id,
      sentence: sentence,
      translation: translation,
      difficulty: 'easy',
    );
    expect(withSentence1, isNotNull);
    expect(await xpManager.getTotalXP(forceRefresh: true), 15);

    // Add the same sentence again (double-tap / retry scenario).
    final withSentence2 = await appState.addSentenceToWord(
      wordId: word.id,
      sentence: sentence,
      translation: translation,
      difficulty: 'easy',
    );
    expect(withSentence2, isNotNull);
    expect(await xpManager.getTotalXP(forceRefresh: true), 15,
        reason: 'Idempotency should prevent double XP');

    final localDb = LocalDatabaseService();
    final localWords = await localDb.getAllWords();
    expect(localWords.length, 1);
    expect(localWords.first.sentences.length, 2,
        reason: 'Local DB may contain duplicate rows before cleanup');

    connectivity.online = true;
    syncService.resetStatusForTesting();
    await syncService.syncPendingChanges();

    final afterSyncWords = await localDb.getAllWords();
    expect(afterSyncWords.length, 1);
    expect(afterSyncWords.first.sentences.length, 1,
        reason: 'Sync should clean duplicate sentence rows');

    await appState.refreshWords();
    expect(appState.allWords.length, 1);
    expect(appState.allWords.first.sentences.length, 1);
    expect(await xpManager.getTotalXP(forceRefresh: true), 15);

    // If a duplicate existed and user deletes one copy, XP should not be deducted twice.
    // Here we only have one remaining, so deleting it should deduct exactly 5.
    final remainingWord = appState.allWords.first;
    final remainingSentenceId = remainingWord.sentences.first.id;
    final deleted = await appState.deleteSentenceFromWord(
      wordId: remainingWord.id,
      sentenceId: remainingSentenceId,
    );
    expect(deleted, isTrue);
    expect(await xpManager.getTotalXP(forceRefresh: true), 10);
  });

  test(
      'Sentence localId->serverId mapping merges cleanly when server row already exists (no duplicates)',
      () async {
    final localDb = LocalDatabaseService();
    final db = await localDb.database;

    // Create a local-only word + sentence (offline).
    final localWordId = await localDb.createWordOffline(
      english: 'MergeWord',
      turkish: 'Birlestir',
      addedDate: DateTime.now(),
      difficulty: 'easy',
    );
    expect(localWordId, lessThan(0));
    expect((await db.query('words')).length, 1);

    final localSentenceId = await localDb.addSentenceToWordOffline(
      wordId: localWordId,
      sentence: 'This sentence will be merged.',
      translation: 'Bu cumle birlestirilecek.',
      difficulty: 'easy',
    );
    expect(localSentenceId, lessThan(0));
    expect((await db.query('sentences')).length, 1);

    // Simulate the word being synced to server.
    const serverWordId = 5555;
    await localDb.updateLocalIdToServerId('words', localWordId, serverWordId);
    expect((await db.query('words')).length, 1);

    // Simulate a server fetch/background save that already inserted the server sentence row locally
    // before the queued local sentence mapping runs.
    const serverSentenceId = 7777;
    await localDb.saveWord(
      Word(
        id: serverWordId,
        englishWord: 'MergeWord',
        turkishMeaning: 'Birlestir',
        learnedDate: DateTime.now(),
        difficulty: 'easy',
        notes: '',
        sentences: [
          Sentence(
            id: serverSentenceId,
            sentence: 'This sentence will be merged.',
            translation: 'Bu cumle birlestirilecek.',
            wordId: serverWordId,
            difficulty: 'easy',
          )
        ],
      ),
    );
    expect((await db.query('words')).length, 1);
    expect((await db.query('sentences')).length, 2,
        reason: 'We should have both local+server sentence rows before merging');

    // Now map the local sentence id to the server id. This used to create duplicates due to PK conflicts.
    await localDb.updateLocalIdToServerId(
      'sentences',
      localSentenceId,
      serverSentenceId,
    );
    await localDb.cleanupDuplicateSentencesForWord(serverWordId);
    expect((await db.query('words')).length, 1);

    final words = await localDb.getAllWords();
    expect(words.length, 1);
    expect(words.first.id, serverWordId);
    expect(words.first.sentences.length, 1,
        reason: 'Local duplicate row should be removed during merge');
    expect(words.first.sentences.first.id, serverSentenceId);
  });

  test(
      'Pending sentence delete prevents resurrection during server refresh (tombstone behavior)',
      () async {
    final localDb = LocalDatabaseService();

    // Create a server-like word+sentence in local DB (as if fetched online earlier).
    const serverWordId = 90001;
    const serverSentenceId = 90002;
    await localDb.saveWord(
      Word(
        id: serverWordId,
        englishWord: 'Tombstone',
        turkishMeaning: 'Mezar tasi',
        learnedDate: DateTime.now(),
        difficulty: 'easy',
        notes: '',
        sentences: [
          Sentence(
            id: serverSentenceId,
            sentence: 'This should stay deleted locally.',
            translation: 'Bu lokalde silinmis kalmali.',
            wordId: serverWordId,
            difficulty: 'easy',
          )
        ],
      ),
    );

    // User deletes the sentence offline (local row removed) and a delete action is queued.
    await localDb.deleteSentenceFromWord(serverWordId, serverSentenceId);
    await localDb.addToSyncQueue(
      'delete',
      'sentences',
      serverSentenceId.toString(),
      {'wordId': serverWordId},
    );

    // A background server refresh arrives BEFORE the delete is processed.
    // The server still returns the sentence, but local DB must not resurrect it.
    await localDb.saveAllWords([
      Word(
        id: serverWordId,
        englishWord: 'Tombstone',
        turkishMeaning: 'Mezar tasi',
        learnedDate: DateTime.now(),
        difficulty: 'easy',
        notes: '',
        sentences: [
          Sentence(
            id: serverSentenceId,
            sentence: 'This should stay deleted locally.',
            translation: 'Bu lokalde silinmis kalmali.',
            wordId: serverWordId,
            difficulty: 'easy',
          )
        ],
      )
    ]);

    final wordsAfter = await localDb.getAllWords();
    expect(wordsAfter.length, 1);
    expect(wordsAfter.first.id, serverWordId);
    expect(
      wordsAfter.first.sentences.any((s) => s.id == serverSentenceId),
      isFalse,
      reason: 'Pending delete should prevent local resurrection until server delete succeeds',
    );
  });

  test(
      'Online delete keeps sentence tombstone when server delete is a no-op',
      () async {
    final localDb = LocalDatabaseService();
    final api = NoOpDeleteSyncApiService();
    syncService.setDependenciesForTesting(
      apiService: api,
      connectivity: connectivity,
    );
    syncService.resetStatusForTesting();
    connectivity.online = true;

    const serverWordId = 91001;
    const serverSentenceId = 91002;
    final serverWord = Word(
      id: serverWordId,
      englishWord: 'MismatchWord',
      turkishMeaning: 'Uyumsuz Kelime',
      learnedDate: DateTime.now(),
      difficulty: 'easy',
      notes: '',
      sentences: [
        Sentence(
          id: serverSentenceId,
          sentence: 'This sentence should not resurrect.',
          translation: 'Bu cumle geri dirilmemeli.',
          wordId: serverWordId,
          difficulty: 'easy',
        ),
      ],
    );

    api.seedServerWord(serverWord);
    await localDb.saveWord(serverWord);

    await appState.refreshWords();
    await appState.refreshSentences();
    expect(
      appState.allSentences.any((s) => !s.isPractice && s.id == serverSentenceId),
      isTrue,
    );

    final deleted = await appState.deleteSentenceFromWord(
      wordId: serverWordId,
      sentenceId: serverSentenceId,
    );
    expect(deleted, isTrue);

    final localAfterDelete = await localDb.getAllWords();
    expect(localAfterDelete.length, 1);
    expect(
      localAfterDelete.first.sentences.any((s) => s.id == serverSentenceId),
      isFalse,
    );

    final queueAfterDelete = await localDb.getPendingSyncItems();
    final hasSentenceDeleteTombstone = queueAfterDelete.any((item) =>
        item['tableName']?.toString() == 'sentences' &&
        item['action']?.toString() == 'delete' &&
        item['itemId']?.toString() == serverSentenceId.toString());
    expect(hasSentenceDeleteTombstone, isTrue,
        reason: 'Server still keeps the sentence, so delete must stay queued');

    await localDb.saveAllWords(await api.getAllWords());
    await appState.refreshWords();
    await appState.refreshSentences();

    expect(
      appState.allSentences.any((s) => !s.isPractice && s.id == serverSentenceId),
      isFalse,
      reason: 'Pending delete tombstone should block resurrection on refresh',
    );
  });

  test(
      'Online delete clears sentence tombstone when server delete succeeds',
      () async {
    final localDb = LocalDatabaseService();
    final api = FakeSyncApiService();
    syncService.setDependenciesForTesting(
      apiService: api,
      connectivity: connectivity,
    );
    syncService.resetStatusForTesting();
    connectivity.online = true;

    const serverWordId = 92001;
    const serverSentenceId = 92002;
    final serverWord = Word(
      id: serverWordId,
      englishWord: 'HappyPathWord',
      turkishMeaning: 'Mutlu Yol',
      learnedDate: DateTime.now(),
      difficulty: 'easy',
      notes: '',
      sentences: [
        Sentence(
          id: serverSentenceId,
          sentence: 'This sentence should stay deleted.',
          translation: 'Bu cumle silinmis kalmali.',
          wordId: serverWordId,
          difficulty: 'easy',
        ),
      ],
    );

    api.seedServerWord(serverWord);
    await localDb.saveWord(serverWord);

    final deleted = await appState.deleteSentenceFromWord(
      wordId: serverWordId,
      sentenceId: serverSentenceId,
    );
    expect(deleted, isTrue);

    final queueAfterDelete = await localDb.getPendingSyncItems();
    final hasSentenceDeleteTombstone = queueAfterDelete.any((item) =>
        item['tableName']?.toString() == 'sentences' &&
        item['action']?.toString() == 'delete' &&
        item['itemId']?.toString() == serverSentenceId.toString());
    expect(hasSentenceDeleteTombstone, isFalse,
        reason: 'Delete succeeded on server; tombstone should be removed');

    await localDb.saveAllWords(await api.getAllWords());
    await appState.refreshWords();
    await appState.refreshSentences();
    expect(
      appState.allSentences.any((s) => !s.isPractice && s.id == serverSentenceId),
      isFalse,
    );
  });

  test(
      'Stale sentence VM (local id) is removed when deleting by server id after sync (offline->online->offline)',
      () async {
    // Offline start.
    connectivity.online = false;

    final word = await appState.addWord(
      english: 'StaleVm',
      turkish: 'EskiVm',
      addedDate: DateTime.now(),
      difficulty: 'easy',
      source: 'manual',
    );
    expect(word, isNotNull);
    expect(word!.id, lessThan(0));

    const sentenceText = 'Stale VM should be removed.';
    const translationText = 'Eski VM kaldirilmali.';

    final withSentence = await appState.addSentenceToWord(
      wordId: word.id,
      sentence: sentenceText,
      translation: translationText,
      difficulty: 'easy',
    );
    expect(withSentence, isNotNull);
    // This inserts a sentence VM with local negative id into _allSentences.
    expect(appState.allSentences.any((s) => !s.isPractice && s.sentence == sentenceText), isTrue);

    // Go online and sync pending creates. Do NOT refreshSentences so stale VM stays in memory.
    connectivity.online = true;
    syncService.resetStatusForTesting();
    await syncService.syncPendingChanges();

    await appState.refreshWords(); // now word/sentence ids are server ids
    final serverWord = appState.allWords.firstWhere((w) => w.englishWord == 'StaleVm');
    expect(serverWord.id, greaterThan(0));
    expect(serverWord.sentences.length, 1);
    final serverSentenceId = serverWord.sentences.first.id;
    expect(serverSentenceId, greaterThan(0));

    // Drop offline and delete by SERVER id. This must also remove the stale local-id VM by content.
    connectivity.online = false;
    final deleted = await appState.deleteSentenceFromWord(
      wordId: serverWord.id,
      sentenceId: serverSentenceId,
    );
    expect(deleted, isTrue);

    // Ensure it is gone from both word and sentences pages state.
    expect(appState.allWords.firstWhere((w) => w.id == serverWord.id).sentences, isEmpty);
    expect(appState.allSentences.any((s) => !s.isPractice && s.sentence == sentenceText), isFalse);
  });

  test(
      'Pending practice sentence delete prevents resurrection during server refresh',
      () async {
    final localDb = LocalDatabaseService();

    // Simulate an existing server practice sentence saved locally.
    const serverPracticeId = 'practice_12345';
    await localDb.savePracticeSentence(
      SentencePractice(
        id: serverPracticeId,
        englishSentence: 'Practice should stay deleted locally.',
        turkishTranslation: 'Pratik lokalde silinmis kalmali.',
        difficulty: 'EASY',
        createdDate: DateTime.now(),
        source: 'practice',
      ),
    );

    // Offline delete: local row removed, delete queued (because it is server id).
    await localDb.deletePracticeSentence(serverPracticeId);
    await localDb.addToSyncQueue(
      'delete',
      'practice_sentences',
      serverPracticeId,
      {},
    );

    // Server refresh arrives before delete is processed.
    await localDb.saveAllPracticeSentences([
      SentencePractice(
        id: serverPracticeId,
        englishSentence: 'Practice should stay deleted locally.',
        turkishTranslation: 'Pratik lokalde silinmis kalmali.',
        difficulty: 'EASY',
        createdDate: DateTime.now(),
        source: 'practice',
      ),
    ]);

    final practice = await localDb.getAllPracticeSentences();
    expect(practice.any((s) => s.id == serverPracticeId), isFalse);
  });

  test('Server refresh removes stale synced word sentences not present on server', () async {
    final localDb = LocalDatabaseService();

    final serverWord = Word(
      id: 2001,
      englishWord: 'stale',
      turkishMeaning: 'bayat',
      learnedDate: DateTime.now(),
      difficulty: 'easy',
      notes: '',
      sentences: [
        Sentence(
          id: 9001,
          sentence: 'keep me',
          translation: 'kalsin',
          wordId: 2001,
          difficulty: 'easy',
        ),
      ],
    );

    // Seed server truth once.
    await localDb.saveAllWords([serverWord]);

    // Inject a stale synced sentence row that the server no longer returns.
    final db = await localDb.database;
    await db.insert('sentences', {
      'id': 9999,
      'localId': null,
      'wordId': 2001,
      'localWordId': null,
      'sentence': 'stale row',
      'translation': 'silinmeli',
      'difficulty': 'easy',
      'syncStatus': 'synced',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Server refresh should reconcile and remove the stale row.
    await localDb.saveAllWords([serverWord]);

    final wordsAfter = await localDb.getAllWords();
    expect(wordsAfter.length, 1);
    expect(wordsAfter.first.sentences.map((s) => s.id).toList(), [9001]);
  });

  test('Server refresh removes stale synced practice sentences not present on server', () async {
    final localDb = LocalDatabaseService();

    final db = await localDb.database;
    await db.insert('practice_sentences', {
      'id': 'practice_9999',
      'localId': null,
      'englishSentence': 'stale practice',
      'turkishTranslation': 'silinmeli',
      'difficulty': 'EASY',
      'createdDate': DateTime.now().toIso8601String().split('T')[0],
      'source': 'practice',
      'syncStatus': 'synced',
      'createdAt': DateTime.now().toIso8601String(),
    });

    final kept = SentencePractice(
      id: 'practice_7001',
      englishSentence: 'keep practice',
      turkishTranslation: 'kalsin',
      difficulty: 'EASY',
      createdDate: DateTime.now(),
      source: 'practice',
    );

    await localDb.saveAllPracticeSentences([kept]);

    final practices = await localDb.getAllPracticeSentences();
    expect(practices.map((s) => s.id).toList(), ['practice_7001']);
  });

  test('Word-source /sentences items are ignored (no ghost sentence in Sentences page)', () async {
    final localDb = LocalDatabaseService();
    final db = await localDb.database;

    // Seed a word + its sentence in the normal word/sentences tables.
    await db.insert('words', {
      'id': 2001,
      'localId': null,
      'englishWord': 'prioritize',
      'turkishMeaning': 'onceliklendirmek',
      'learnedDate': DateTime.now().toIso8601String().split('T')[0],
      'notes': '',
      'difficulty': 'easy',
      'syncStatus': 'synced',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.insert('sentences', {
      'id': 9001,
      'localId': null,
      'wordId': 2001,
      'localWordId': null,
      'sentence': 'I will prioritize my tasks.',
      'translation': 'Islerimi onceliklendirecegim.',
      'difficulty': 'easy',
      'syncStatus': 'synced',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Seed a cached "word_" sentence in practice_sentences (from /api/sentences combined endpoint).
    // This must NOT show up as an independent practice sentence in Sentences page.
    await db.insert('practice_sentences', {
      'id': 'word_9001',
      'localId': null,
      'englishSentence': 'I will prioritize my tasks.',
      'turkishTranslation': 'Islerimi onceliklendirecegim.',
      'difficulty': 'easy',
      'createdDate': DateTime.now().toIso8601String().split('T')[0],
      'source': 'word',
      'syncStatus': 'synced',
      'createdAt': DateTime.now().toIso8601String(),
    });

    await appState.refreshWords();
    await appState.refreshSentences();

    final all = appState.allSentences;
    expect(all.where((s) => s.isPractice).length, 0);
    expect(all.where((s) => !s.isPractice).length, 1);
    expect(all.first.id, 9001);
  });
}
