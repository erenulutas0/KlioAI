import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:vocabmaster/services/offline_sync_service.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/xp_manager.dart';
import 'package:vocabmaster/services/local_database_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vocabmaster/models/word.dart';
import '../test_helper.dart';

// Mocks
class ManualMockApiService extends Mock implements ApiService {
  @override
  Future<Word> createWord({
    required String english,
    required String turkish,
    required DateTime addedDate,
    String difficulty = 'easy',
  }) =>
      super.noSuchMethod(
        Invocation.method(#createWord, [], {
          #english: english,
          #turkish: turkish,
          #addedDate: addedDate,
          #difficulty: difficulty,
        }),
        returnValue: Future.value(Word(
          id: 1001,
          englishWord: english,
          turkishMeaning: turkish,
          difficulty: difficulty,
          learnedDate: addedDate,
          notes: '',
          sentences: [],
        )),
      );
}

class ManualMockConnectivity extends Mock implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      super.noSuchMethod(Invocation.method(#checkConnectivity, []),
          returnValue: Future.value([ConnectivityResult.none]));

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.none]);
}

void main() {
  late OfflineSyncService syncService;
  late ManualMockApiService mockApiService;
  late ManualMockConnectivity mockConnectivity;
  late LocalDatabaseService localDb;

  setUpAll(() {
    setupTestEnv();
  });

  setUp(() async {
    await clearDatabase();

    syncService = OfflineSyncService();
    mockApiService = ManualMockApiService();
    mockConnectivity = ManualMockConnectivity();
    localDb = LocalDatabaseService();

    // Inject mocks
    syncService.setDependenciesForTesting(
      apiService: mockApiService,
      connectivity: mockConnectivity,
    );
    syncService.resetStatusForTesting();
    XPManager.resetIdempotency();
  });

  group('Offline Sync Service Tests', () {
    test('Offline Mode: Creating word adds to local DB and Sync Queue',
        () async {
      // 1. Force Offline State
      when(mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      // Ensure sync service thinks it's offline
      // We can't easily force private _isOnline, but checkConnectivity logic sets it.
      // However, checkConnectivity also tries to ping google.com often.
      // Let's rely on the method result.

      // 2. Perform Action: Add Word
      final newWord = await syncService.createWord(
        english: 'OfflineWord',
        turkish: 'Çevrimdışı',
        addedDate: DateTime.now(),
        difficulty: 'medium',
      );

      expect(newWord, isNotNull);
      expect(newWord!.englishWord, 'OfflineWord');

      // 3. Verify Local DB has the word
      final words = await localDb.getAllWords();
      expect(words.length, 1);
      expect(words.first.englishWord, 'OfflineWord');

      // 4. Verify Sync Queue has the item
      // Background sync takes a moment
      await Future.delayed(Duration(milliseconds: 200));

      final queue = await localDb.getSyncQueue();
      expect(queue.length, 1, reason: 'Queue should have 1 pending item');

      final item = queue.first;
      expect(item['action'], 'create');
      expect(item['status'], 'pending');

      final dataStr = item['data']; // Changed from payload to data
      expect(dataStr, contains('OfflineWord'));
    });

    test('Online Mode: Creating word calls API directly (Simulated)', () async {
      // 1. Force Online State simulation
      when(mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      final testDate = DateTime.now();

      // 2. Mock ApiService.createWord to succeed.
      // We use specific values instead of anyNamed to avoid null-safety issues with manual mocks
      when(mockApiService.createWord(
        english: 'OnlineWord',
        turkish: 'Çevrimiçi',
        addedDate: testDate,
        difficulty: 'hard',
      )).thenAnswer((_) async => Word(
            id: 1001,
            englishWord: 'OnlineWord',
            turkishMeaning: 'Çevrimiçi',
            difficulty: 'hard',
            learnedDate: testDate,
            notes: '',
            sentences: [],
          ));

      // 3. Perform Action
      final result = await syncService.createWord(
        english: 'OnlineWord',
        turkish: 'Çevrimiçi',
        addedDate: testDate,
        difficulty: 'hard',
      );

      expect(result, isNotNull);
      expect(result!.id,
          lessThan(0)); // Optimistic update returns localId initially

      // 4. Verify Local DB also has it
      // Wait for background sync to finish - may take longer on slow CI or Windows
      await Future.delayed(Duration(milliseconds: 300));

      final words = await localDb.getAllWords();
      expect(words.length, 1);
      print('DEBUG: words.first.id=${words.first.id}');
      expect(words.first.englishWord, 'OnlineWord');
      expect(words.first.id, 1001); // Check if serverId was updated in local DB

      // 5. Verify Queue is Empty (direct success should not queue)
      final queue = await localDb.getSyncQueue();
      expect(queue.isEmpty, true,
          reason: 'Queue should be empty for online success');
    });

    test('Delete sentence should work with stale local wordId after ID mapping',
        () async {
      when(mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      final localWordId = await localDb.createWordOffline(
        english: 'MappedWord',
        turkish: 'Eslestirilmis',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );

      final localSentenceId = await localDb.addSentenceToWordOffline(
        wordId: localWordId,
        sentence: 'Mapped sentence',
        translation: 'Eslestirilmis cumle',
        difficulty: 'easy',
      );

      await localDb.updateLocalIdToServerId('words', localWordId, 501);
      await localDb.updateLocalIdToServerId('sentences', localSentenceId, 9001);

      // Simulate a server-only linked sentence row where localWordId is lost.
      final db = await localDb.database;
      await db.update(
        'sentences',
        {'wordId': 501, 'localWordId': null},
        where: 'id = ?',
        whereArgs: [9001],
      );

      final before =
          await db.query('sentences', where: 'id = ?', whereArgs: [9001]);
      expect(before, isNotEmpty);

      final deleted = await syncService.deleteSentenceFromWord(
        wordId: localWordId, // stale UI/local ID
        sentenceId: 9001, // mapped server sentence ID
      );

      expect(deleted, isTrue);

      final after =
          await db.query('sentences', where: 'id = ?', whereArgs: [9001]);
      expect(after, isEmpty);
    });

    test('Sync queue health snapshot reports counts by action and table',
        () async {
      when(mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      await syncService.createWord(
        english: 'HealthWord',
        turkish: 'Saglik',
        addedDate: DateTime.now(),
        difficulty: 'easy',
      );

      await localDb.addToSyncQueue(
        'delete',
        'sentences',
        '777',
        {'wordId': 1},
      );

      final health = await syncService.getSyncQueueHealth();
      final byTable =
          Map<String, dynamic>.from(health['byTable'] as Map<dynamic, dynamic>);

      expect(health['pendingTotal'], 2);
      expect(health['createCount'], 1);
      expect(health['deleteCount'], 1);
      expect(byTable['words'], 1);
      expect(byTable['sentences'], 1);
      expect(health['isOnline'], isFalse);
      expect(health['isSyncing'], isFalse);
      expect(health['oldestPendingSeconds'], isA<int>());
    });
  });
}
