import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/word.dart';
import '../models/sentence_practice.dart';

/// Yerel SQLite veritabanı yönetimi
/// Offline modu destekler ve senkronizasyon için pending işlemleri takip eder
class LocalDatabaseService {
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _database;
  String? _dbPath;
  static bool _forceTestMode = false;

  @visibleForTesting
  static void enableTestMode() {
    _forceTestMode = true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final isTest = _forceTestMode || const bool.fromEnvironment('FLUTTER_TEST');
    final dbName = isTest
        ? 'vocabmaster_offline_test_${Isolate.current.hashCode}.db'
        : 'vocabmaster_offline.db';
    final path = join(dbPath, dbName);
    _dbPath = path;

    return await openDatabase(
      path,
      version: 2,
      singleInstance: !isTest,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS xp_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actionId TEXT NOT NULL,
            actionName TEXT NOT NULL,
            amount INTEGER NOT NULL,
            source TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
      },
    );
  }

  @visibleForTesting
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Words tablosu
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY,
        localId INTEGER,
        englishWord TEXT NOT NULL,
        turkishMeaning TEXT NOT NULL,
        learnedDate TEXT NOT NULL,
        notes TEXT,
        difficulty TEXT DEFAULT 'easy',
        syncStatus TEXT DEFAULT 'synced',
        createdAt TEXT NOT NULL
      )
    ''');

    // Sentences tablosu (kelimelere ait)
    await db.execute('''
      CREATE TABLE sentences (
        id INTEGER PRIMARY KEY,
        localId INTEGER,
        wordId INTEGER,
        localWordId INTEGER,
        sentence TEXT NOT NULL,
        translation TEXT NOT NULL,
        difficulty TEXT,
        syncStatus TEXT DEFAULT 'synced',
        createdAt TEXT NOT NULL,
        FOREIGN KEY (wordId) REFERENCES words(id)
      )
    ''');

    // Practice sentences tablosu (bağımsız cümleler)
    await db.execute('''
      CREATE TABLE practice_sentences (
        id TEXT PRIMARY KEY,
        localId INTEGER,
        englishSentence TEXT NOT NULL,
        turkishTranslation TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        createdDate TEXT NOT NULL,
        source TEXT DEFAULT 'practice',
        syncStatus TEXT DEFAULT 'synced',
        createdAt TEXT NOT NULL
      )
    ''');

    // XP ve kullanıcı istatistikleri tablosu
    await db.execute('''
      CREATE TABLE user_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        totalXp INTEGER DEFAULT 0,
        lastSyncedXp INTEGER DEFAULT 0,
        pendingXp INTEGER DEFAULT 0,
        lastUpdated TEXT NOT NULL
      )
    ''');

    // Pending sync queue tablosu
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        tableName TEXT NOT NULL,
        itemId TEXT NOT NULL,
        data TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // XP geçmişi tablosu
    await db.execute('''
      CREATE TABLE xp_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actionId TEXT NOT NULL,
        actionName TEXT NOT NULL,
        amount INTEGER NOT NULL,
        source TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    // İlk kullanıcı stats kaydı
    await db.insert('user_stats', {
      'totalXp': 0,
      'lastSyncedXp': 0,
      'pendingXp': 0,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Yeni tablolar ekle
      await _onCreate(db, newVersion);
    }
    // XP history tablosu eksikse ekle (korumalı)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS xp_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actionId TEXT NOT NULL,
        actionName TEXT NOT NULL,
        amount INTEGER NOT NULL,
        source TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  // ==================== WORDS ====================

  int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  DateTime? _tryParseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Future<Set<int>> _getPendingDeleteIds(String tableName) async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      columns: ['itemId'],
      where: 'tableName = ? AND action = ? AND status = ?',
      whereArgs: [tableName, 'delete', 'pending'],
    );
    final ids = <int>{};
    for (final row in rows) {
      final raw = row['itemId']?.toString() ?? '';
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed != 0) {
        ids.add(parsed);
      }
    }
    return ids;
  }

  Future<Set<String>> _getPendingDeleteItemIds(String tableName) async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      columns: ['itemId'],
      where: 'tableName = ? AND action = ? AND status = ?',
      whereArgs: [tableName, 'delete', 'pending'],
    );
    final ids = <String>{};
    for (final row in rows) {
      final raw = row['itemId']?.toString() ?? '';
      if (raw.trim().isEmpty) continue;
      ids.add(raw.trim());
    }
    return ids;
  }

  /// Tüm kelimeleri getir (yerel)
  Future<List<Word>> getAllWords() async {
    final db = await database;
    final List<Map<String, dynamic>> wordMaps =
        await db.query('words', orderBy: 'learnedDate DESC');

    List<Word> words = [];
    for (var wordMap in wordMaps) {
      final rawWordId = wordMap['id'];
      final rawLocalId = wordMap['localId'];
      final intWordId = (rawWordId is int)
          ? rawWordId
          : (rawWordId is num)
              ? rawWordId.toInt()
              : 0;
       final intLocalId = (rawLocalId is int)
           ? rawLocalId
           : (rawLocalId is num)
               ? rawLocalId.toInt()
               : intWordId;
       final sentences = await db.query(
         'sentences',
         where: 'wordId = ? OR localWordId = ?',
         whereArgs: [intWordId, intLocalId],
         orderBy: 'createdAt DESC',
       );

       words.add(Word(
         id: intWordId != 0 ? intWordId : intLocalId,
         englishWord: wordMap['englishWord'] ?? '',
        turkishMeaning: wordMap['turkishMeaning'] ?? '',
        learnedDate: DateTime.parse(wordMap['learnedDate']),
        notes: wordMap['notes'],
        difficulty: wordMap['difficulty'] ?? 'easy',
         sentences: sentences
             .map((s) => Sentence(
                   id: s['id'] as int? ?? s['localId'] as int? ?? 0,
                   sentence: s['sentence'] as String? ?? '',
                   translation: s['translation'] as String? ?? '',
                   wordId: wordMap['id'] ?? wordMap['localId'] ?? 0,
                   difficulty: s['difficulty'] as String?,
                   createdAt: _tryParseDateTime(s['createdAt']),
                 ))
             .toList(),
       ));
     }

     return words;
  }

  /// Kelime kaydet (online'dan gelen)
  Future<void> saveWord(Word word) async {
    final db = await database;
    final pendingWordDeletes = await _getPendingDeleteIds('words');
    final pendingSentenceDeletes = await _getPendingDeleteIds('sentences');

    // Do not resurrect locally-deleted content while a delete is pending in the queue.
    if (pendingWordDeletes.contains(word.id)) {
      await db.delete('words', where: 'id = ? OR localId = ?', whereArgs: [word.id, word.id]);
      await db.delete('sentences', where: 'wordId = ? OR localWordId = ?', whereArgs: [word.id, word.id]);
      return;
    }

    final existingWordRow = await db.query(
      'words',
      columns: ['localId', 'createdAt'],
      where: 'id = ?',
      whereArgs: [word.id],
      limit: 1,
    );
    final preservedWordLocalId = existingWordRow.isNotEmpty
        ? _toNullableInt(existingWordRow.first['localId'])
        : null;
    final preservedWordCreatedAt = existingWordRow.isNotEmpty
        ? (existingWordRow.first['createdAt']?.toString())
        : null;

    await db.insert(
        'words',
        {
          'id': word.id,
          'localId': preservedWordLocalId,
          'englishWord': word.englishWord,
          'turkishMeaning': word.turkishMeaning,
          'learnedDate': word.learnedDate.toIso8601String().split('T')[0],
          'notes': word.notes,
          'difficulty': word.difficulty,
          'syncStatus': 'synced',
          'createdAt': preservedWordCreatedAt ?? DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    // Reconcile server truth: remove locally-synced sentence rows that no longer exist on server.
    // Keep pending local (offline) sentences so the user doesn't lose work while offline.
    final linkedLocalWordId = preservedWordLocalId ?? word.id;
    final existingSentenceRowsForWord = await db.query(
      'sentences',
      columns: ['id', 'localId', 'localWordId', 'createdAt'],
      where: 'wordId = ? OR localWordId = ?',
      whereArgs: [word.id, linkedLocalWordId],
    );
    final existingSentenceLocalIds = <int, int?>{};
    final existingSentenceLocalWordIds = <int, int?>{};
    final existingSentenceCreatedAts = <int, String?>{};
    for (final row in existingSentenceRowsForWord) {
      final id = _toNullableInt(row['id']);
      if (id != null) {
        existingSentenceLocalIds[id] = _toNullableInt(row['localId']);
        existingSentenceLocalWordIds[id] = _toNullableInt(row['localWordId']);
        existingSentenceCreatedAts[id] = row['createdAt']?.toString();
      }
    }
    await db.delete(
      'sentences',
      where: '(wordId = ? OR localWordId = ?) AND syncStatus != ?',
      whereArgs: [word.id, linkedLocalWordId, 'pending'],
    );

    // Sentences kaydet
    for (var sentence in word.sentences) {
      if (pendingSentenceDeletes.contains(sentence.id)) {
        // Ensure the local row stays deleted until the server delete is confirmed.
        await db.delete('sentences', where: 'id = ?', whereArgs: [sentence.id]);
        continue;
      }
      final preservedSentenceLocalId = existingSentenceLocalIds[sentence.id];
      final preservedLocalWordId = existingSentenceLocalWordIds[sentence.id];
      final preservedSentenceCreatedAt = existingSentenceCreatedAts[sentence.id];

      await db.insert(
          'sentences',
          {
            'id': sentence.id,
            'localId': preservedSentenceLocalId,
            'wordId': word.id,
            'localWordId': preservedLocalWordId,
            'sentence': sentence.sentence,
            'translation': sentence.translation,
            'difficulty': sentence.difficulty,
            'syncStatus': 'synced',
            'createdAt': preservedSentenceCreatedAt ??
                sentence.createdAt?.toIso8601String() ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Tüm kelimeleri kaydet (bulk)
  Future<void> saveAllWords(List<Word> words) async {
    final db = await database;
    final pendingWordDeletes = await _getPendingDeleteIds('words');
    final pendingSentenceDeletes = await _getPendingDeleteIds('sentences');
    final batch = db.batch();
    final existingWordRows =
        await db.query('words', columns: ['id', 'localId', 'createdAt']);
    final existingWordLocalIds = <int, int?>{};
    final existingWordCreatedAts = <int, String?>{};
    for (final row in existingWordRows) {
      final id = _toNullableInt(row['id']);
      if (id != null) {
        existingWordLocalIds[id] = _toNullableInt(row['localId']);
        existingWordCreatedAts[id] = row['createdAt']?.toString();
      }
    }
    final existingSentenceRows =
        await db.query('sentences', columns: ['id', 'localId', 'localWordId', 'createdAt']);
    final existingSentenceLocalIds = <int, int?>{};
    final existingSentenceLocalWordIds = <int, int?>{};
    final existingSentenceCreatedAts = <int, String?>{};
    for (final row in existingSentenceRows) {
      final id = _toNullableInt(row['id']);
      if (id != null) {
        existingSentenceLocalIds[id] = _toNullableInt(row['localId']);
        existingSentenceLocalWordIds[id] = _toNullableInt(row['localWordId']);
        existingSentenceCreatedAts[id] = row['createdAt']?.toString();
      }
    }

    for (var word in words) {
      if (pendingWordDeletes.contains(word.id)) {
        // Keep local deletion consistent while delete is pending.
        batch.delete('words', where: 'id = ? OR localId = ?', whereArgs: [word.id, word.id]);
        batch.delete('sentences', where: 'wordId = ? OR localWordId = ?', whereArgs: [word.id, word.id]);
        continue;
      }
      batch.insert(
          'words',
          {
            'id': word.id,
            'localId': existingWordLocalIds[word.id],
            'englishWord': word.englishWord,
            'turkishMeaning': word.turkishMeaning,
            'learnedDate': word.learnedDate.toIso8601String().split('T')[0],
            'notes': word.notes,
            'difficulty': word.difficulty,
            'syncStatus': 'synced',
            'createdAt': existingWordCreatedAts[word.id] ??
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      // Reconcile server truth: delete locally-synced sentence rows for this word before inserting the
      // current server set. Keep pending local (offline) sentences.
      final linkedLocalWordId = existingWordLocalIds[word.id] ?? word.id;
      batch.delete(
        'sentences',
        where: '(wordId = ? OR localWordId = ?) AND syncStatus != ?',
        whereArgs: [word.id, linkedLocalWordId, 'pending'],
      );

      for (var sentence in word.sentences) {
        if (pendingSentenceDeletes.contains(sentence.id)) {
          // Prevent resurrection of a sentence the user deleted offline.
          batch.delete('sentences', where: 'id = ?', whereArgs: [sentence.id]);
          continue;
        }
        batch.insert(
            'sentences',
            {
              'id': sentence.id,
              'localId': existingSentenceLocalIds[sentence.id],
              'wordId': word.id,
              'localWordId': existingSentenceLocalWordIds[sentence.id],
              'sentence': sentence.sentence,
              'translation': sentence.translation,
              'difficulty': sentence.difficulty,
              'syncStatus': 'synced',
              'createdAt': existingSentenceCreatedAts[sentence.id] ??
                  sentence.createdAt?.toIso8601String() ??
                  DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    await batch.commit(noResult: true);
  }

  /// Yeni kelime ekle (offline)
  Future<int> createWordOffline({
    required String english,
    required String turkish,
    required DateTime addedDate,
    String difficulty = 'easy',
  }) async {
    final db = await database;

    // Negatif local ID kullan (sync sonrası gerçek ID alınacak)
    final localId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('words', {
      'id': localId,
      'localId': localId,
      'englishWord': english,
      'turkishMeaning': turkish,
      'learnedDate': addedDate.toIso8601String().split('T')[0],
      'notes': '',
      'difficulty': difficulty,
      'syncStatus': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Sync queue'ya ekle
    await addToSyncQueue('create', 'words', localId.toString(), {
      'english': english,
      'turkish': turkish,
      'addedDate': addedDate.toIso8601String(),
      'difficulty': difficulty,
    });

    // NOT: XP ekleme işlemi AppStateProvider/XPManager üzerinden yapılıyor
    // Burada eklenirse çift XP sorunu oluşur

    return localId;
  }

  /// Kelime sil (cascade: cümleleri de siler)
  Future<int> deleteWord(int id) async {
    final db = await database;

    // Önce cümleleri sil
    await db.delete(
      'sentences',
      where: 'wordId = ? OR localWordId = ?',
      whereArgs: [id, id],
    );

    // Sonra kelimeyi sil
    final deletedWords = await db.delete(
      'words',
      where: 'id = ? OR localId = ?',
      whereArgs: [id, id],
    );

    // NOT: XP düşürme işlemi AppStateProvider/XPManager üzerinden yapılıyor
    // Burada yapılırsa UI senkronizasyonu bozulur
    return deletedWords;
  }

  /// Kelimeye cümle ekle (offline)
  Future<int> addSentenceToWordOffline({
    required int wordId,
    required String sentence,
    required String translation,
    String difficulty = 'easy',
  }) async {
    final db = await database;

    final localId = -DateTime.now().millisecondsSinceEpoch;

    await db.insert('sentences', {
      'id': localId,
      'localId': localId,
      'wordId': wordId > 0 ? wordId : null,
      'localWordId': wordId < 0 ? wordId : null,
      'sentence': sentence,
      'translation': translation,
      'difficulty': difficulty,
      'syncStatus': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Sync queue'ya ekle
    await addToSyncQueue('create', 'sentences', localId.toString(), {
      'wordId': wordId,
      'sentence': sentence,
      'translation': translation,
      'difficulty': difficulty,
    });

    // NOT: XP ekleme işlemi AppStateProvider/XPManager üzerinden yapılıyor

    return localId;
  }

  /// Kelimeden cümle sil (local DB)
  Future<int> deleteSentenceFromWord(int wordId, int sentenceId) async {
    final db = await database;

    // Hem id hem de localId ile silmeyi dene
    final deleted = await db.delete(
      'sentences',
      where: '(id = ? OR localId = ?) AND (wordId = ? OR localWordId = ?)',
      whereArgs: [sentenceId, sentenceId, wordId, wordId],
    );

    // NOT: XP düşürme işlemi AppStateProvider/XPManager üzerinden yapılıyor
    return deleted;
  }

  /// Aynı kelime altında (sentence, translation) bazlı tekrar eden cümleleri temizle.
  /// Offline->online ID mapping hatalarında veya double-tap gibi durumlarda UI'da aynı cümlenin
  /// iki kez görünmesini engeller.
  ///
  /// Not: Burada sadece local DB ve queue temizlenir; server tarafını etkilemez.
  Future<int> cleanupDuplicateSentencesForWord(int wordId) async {
    final db = await database;

    int? localWordId;
    if (wordId > 0) {
      final wordRows = await db.query(
        'words',
        columns: ['localId'],
        where: 'id = ?',
        whereArgs: [wordId],
        limit: 1,
      );
      if (wordRows.isNotEmpty) {
        localWordId = _toNullableInt(wordRows.first['localId']);
      }
    } else {
      // For local-only words, the localWordId is the wordId itself (negative).
      localWordId = wordId;
    }

    final ids = <int>{wordId};
    if (localWordId != null) {
      ids.add(localWordId);
    }
    final idList = ids.toList();
    final placeholders = List.filled(idList.length, '?').join(',');

    final rows = await db.query(
      'sentences',
      where:
          'wordId IN ($placeholders) OR localWordId IN ($placeholders)',
      whereArgs: [...idList, ...idList],
    );

    String norm(dynamic value) {
      final raw = (value?.toString() ?? '').trim();
      if (raw.isEmpty) return '';
      return raw.replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();
    }

    int rank(Map<String, dynamic> row) {
      int score = 0;
      final syncStatus = row['syncStatus']?.toString() ?? '';
      final id = _toNullableInt(row['id']) ?? 0;
      if (syncStatus == 'synced') score += 10;
      if (id > 0) score += 5;
      return score;
    }

    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final row in rows) {
      final key = '${norm(row['sentence'])}|||${norm(row['translation'])}';
      groups.putIfAbsent(key, () => []).add(row);
    }

    int deletedCount = 0;
    for (final entry in groups.entries) {
      final items = entry.value;
      if (items.length <= 1) continue;

      items.sort((a, b) {
        final scoreDiff = rank(b) - rank(a);
        if (scoreDiff != 0) return scoreDiff;
        final idA = _toNullableInt(a['id']) ?? 0;
        final idB = _toNullableInt(b['id']) ?? 0;
        return idB.compareTo(idA);
      });

      for (final row in items.skip(1)) {
        final id = _toNullableInt(row['id']);
        final localId = _toNullableInt(row['localId']);
        if (id == null) continue;

        // Delete the duplicate sentence row.
        await db.delete('sentences', where: 'id = ?', whereArgs: [id]);
        deletedCount++;

        // Remove any queued actions for this duplicate row (usually a pending create).
        final candidateItemIds = <String>{id.toString()};
        if (localId != null) {
          candidateItemIds.add(localId.toString());
        }
        for (final itemId in candidateItemIds) {
          await db.delete(
            'sync_queue',
            where: 'tableName = ? AND itemId = ?',
            whereArgs: ['sentences', itemId],
          );
        }
      }
    }

    return deletedCount;
  }

  // ==================== PRACTICE SENTENCES ====================

  /// Tüm practice sentences getir
  Future<List<SentencePractice>> getAllPracticeSentences() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'practice_sentences',
      where: 'source = ?',
      whereArgs: ['practice'],
      orderBy: 'createdDate DESC',
    );

    return maps
        .map((map) => SentencePractice(
              id: map['id'] ?? 'local_${map['localId']}',
              englishSentence: map['englishSentence'] ?? '',
              turkishTranslation: map['turkishTranslation'] ?? '',
              difficulty: map['difficulty'] ?? 'EASY',
              createdDate: DateTime.parse(map['createdDate']),
              source: map['source'] ?? 'practice',
            ))
        .toList();
  }

  /// Practice sentence kaydet (online'dan gelen)
  Future<void> savePracticeSentence(SentencePractice sentence) async {
    final db = await database;
    if (sentence.source != 'practice') {
      // We only persist practice sentences locally; word sentences are read via words->sentences.
      return;
    }
    final pendingDeletes = await _getPendingDeleteItemIds('practice_sentences');
    if (pendingDeletes.contains(sentence.id)) {
      await db.delete('practice_sentences', where: 'id = ?', whereArgs: [sentence.id]);
      return;
    }

    await db.insert(
        'practice_sentences',
        {
          'id': sentence.id,
          'englishSentence': sentence.englishSentence,
          'turkishTranslation': sentence.turkishTranslation,
          'difficulty': sentence.difficulty,
          'createdDate':
              sentence.createdDate?.toIso8601String().split('T')[0] ??
                  DateTime.now().toIso8601String().split('T')[0],
          'source': sentence.source,
          'syncStatus': 'synced',
          'createdAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Tüm practice sentences kaydet (bulk)
  Future<void> saveAllPracticeSentences(
      List<SentencePractice> sentences) async {
    final db = await database;
    // Only practice sentences are persisted locally.
    sentences = sentences.where((s) => s.source == 'practice').toList();

    final pendingDeletes =
        await _getPendingDeleteItemIds('practice_sentences');

    final serverIds =
        sentences.map((s) => s.id).where((id) => id.trim().isNotEmpty).toSet();
    final effectiveServerIds = serverIds.difference(pendingDeletes);

    await db.transaction((txn) async {
      final batch = txn.batch();

      // Reconcile server truth: remove locally-synced rows that are no longer on server.
      // Keep pending local rows (offline-created).
      if (effectiveServerIds.isEmpty) {
        await txn.delete(
          'practice_sentences',
          where: 'syncStatus != ?',
          whereArgs: ['pending'],
        );
      } else {
        final placeholders =
            List.filled(effectiveServerIds.length, '?').join(',');
        await txn.delete(
          'practice_sentences',
          where:
              'syncStatus != ? AND id NOT IN ($placeholders)',
          whereArgs: ['pending', ...effectiveServerIds],
        );
      }

      for (var sentence in sentences) {
        if (pendingDeletes.contains(sentence.id)) {
          batch.delete(
            'practice_sentences',
            where: 'id = ?',
            whereArgs: [sentence.id],
          );
          continue;
        }
        batch.insert(
            'practice_sentences',
            {
              'id': sentence.id,
              'englishSentence': sentence.englishSentence,
              'turkishTranslation': sentence.turkishTranslation,
              'difficulty': sentence.difficulty,
              'createdDate':
                  sentence.createdDate?.toIso8601String().split('T')[0] ??
                      DateTime.now().toIso8601String().split('T')[0],
              'source': sentence.source,
              'syncStatus': 'synced',
              'createdAt': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
    });
  }

  /// Practice sentence oluştur (offline)
  Future<String> createPracticeSentenceOffline({
    required String englishSentence,
    required String turkishTranslation,
    required String difficulty,
  }) async {
    final db = await database;

    final localId = DateTime.now().millisecondsSinceEpoch;
    final id = 'local_$localId';

    await db.insert('practice_sentences', {
      'id': id,
      'localId': localId,
      'englishSentence': englishSentence,
      'turkishTranslation': turkishTranslation,
      'difficulty': difficulty.toUpperCase(),
      'createdDate': DateTime.now().toIso8601String().split('T')[0],
      'source': 'practice',
      'syncStatus': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Sync queue'ya ekle
    await _addToSyncQueue('create', 'practice_sentences', id, {
      'englishSentence': englishSentence,
      'turkishTranslation': turkishTranslation,
      'difficulty': difficulty.toUpperCase(),
    });

    // NOT: XP ekleme işlemi AppStateProvider/XPManager üzerinden yapılıyor

    return id;
  }

  /// Practice sentence sil
  Future<int> deletePracticeSentence(String id) async {
    final db = await database;
    final deleted =
        await db.delete('practice_sentences', where: 'id = ?', whereArgs: [id]);

    // NOT: XP düşürme işlemi AppStateProvider/XPManager üzerinden yapılıyor
    return deleted;
  }

  // ==================== XP MANAGEMENT ====================

  /// XP ekle
  Future<void> addXp(int amount) async {
    final db = await database;

    // Check if update affects any rows
    final changes = await db.rawUpdate('''
      UPDATE user_stats 
      SET totalXp = totalXp + ?,
          pendingXp = pendingXp + ?,
          lastUpdated = ?
    ''', [amount, amount, DateTime.now().toIso8601String()]);

    // If table is empty, insert first row
    if (changes == 0) {
      await db.insert('user_stats', {
        'totalXp': amount,
        'lastSyncedXp': 0,
        'pendingXp': amount,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    }
  }

  /// XP düşür (silme işlemlerinde)
  Future<void> deductXp(int amount) async {
    final db = await database;

    // XP'yi düşür ama 0'ın altına düşürme
    await db.rawUpdate('''
      UPDATE user_stats 
      SET totalXp = MAX(0, totalXp - ?),
          pendingXp = pendingXp - ?,
          lastUpdated = ?
    ''', [amount, amount, DateTime.now().toIso8601String()]);
  }

  /// Toplam XP getir
  Future<int> getTotalXp() async {
    final db = await database;
    final result = await db.query('user_stats', limit: 1);
    if (result.isNotEmpty) {
      return result.first['totalXp'] as int? ?? 0;
    }
    return 0;
  }

  /// Pending XP getir (sync edilecek)
  Future<int> getPendingXp() async {
    final db = await database;
    final result = await db.query('user_stats', limit: 1);
    if (result.isNotEmpty) {
      return result.first['pendingXp'] as int? ?? 0;
    }
    return 0;
  }

  /// XP sync edildi olarak işaretle
  Future<void> markXpSynced() async {
    final db = await database;
    final totalXp = await getTotalXp();
    await db.update('user_stats', {
      'lastSyncedXp': totalXp,
      'pendingXp': 0,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  /// Online XP ile senkronize et
  Future<void> syncXpFromServer(int serverXp) async {
    final db = await database;
    final pendingXp = await getPendingXp();

    // Server XP + pending XP (offline'da kazanılan)
    final newTotalXp = serverXp + pendingXp;

    await db.update('user_stats', {
      'totalXp': newTotalXp,
      'lastSyncedXp': serverXp,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  // ==================== SYNC QUEUE ====================

  Future<void> _addToSyncQueue(String action, String tableName, String itemId,
      Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('sync_queue', {
      'action': action,
      'tableName': tableName,
      'itemId': itemId,
      'data': jsonEncode(data), // JSON olarak saklanabilir
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
  }

  /// Bekleyen sync işlemlerini getir
  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'createdAt ASC',
    );
  }

  /// Sync işlemi tamamlandı olarak işaretle
  Future<void> markSyncItemCompleted(int id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 'completed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Pending items update after sync (lokalden sunucuya eşleşme)
  Future<void> updateLocalIdToServerId(
      String tableName, int localId, int serverId) async {
    final db = await database;

    if (tableName == 'words') {
      await db.transaction((txn) async {
        // Prefer matching the true local row by `id == localId` (offline inserts use id=localId).
        final localRowsById = await txn.query(
          'words',
          where: 'id = ?',
          whereArgs: [localId],
          limit: 1,
        );
        final localRows = localRowsById.isNotEmpty
            ? localRowsById
            : await txn.query(
                'words',
                where: 'localId = ?',
                whereArgs: [localId],
                limit: 1,
              );
        final serverRows = await txn.query(
          'words',
          where: 'id = ?',
          whereArgs: [serverId],
          limit: 1,
        );

        if (serverRows.isNotEmpty) {
          // Merge: keep server row id, attach localId if missing, remove local row.
          final serverLocalId = _toNullableInt(serverRows.first['localId']);
          final serverCreatedAt = serverRows.first['createdAt']?.toString();
          final localCreatedAt = localRows.isNotEmpty
              ? localRows.first['createdAt']?.toString()
              : null;

          final updates = <String, dynamic>{
            'syncStatus': 'synced',
          };
          if (serverLocalId == null) {
            updates['localId'] = localId;
          }
          if (serverCreatedAt == null && localCreatedAt != null) {
            updates['createdAt'] = localCreatedAt;
          }
          if (updates.length > 1) {
            await txn.update(
              'words',
              updates,
              where: 'id = ?',
              whereArgs: [serverId],
            );
          }

          // Ensure sentences link to the server word id.
          await txn.update(
            'sentences',
            {'wordId': serverId},
            where: 'wordId = ? OR localWordId = ?',
            whereArgs: [localId, localId],
          );

          // Remove the old local word row (if any).
          if (localRows.isNotEmpty) {
            final localRowId = _toNullableInt(localRows.first['id']) ?? localId;
            if (localRowId != serverId) {
              await txn.delete(
                'words',
                where: 'id = ?',
                whereArgs: [localRowId],
              );
            }
          }
        } else {
          // No server row yet: safe to update the local row id -> serverId.
          await txn.update(
            'words',
            {'id': serverId, 'syncStatus': 'synced'},
            where: 'localId = ? OR id = ?',
            whereArgs: [localId, localId],
          );
          await txn.update(
            'sentences',
            {'wordId': serverId},
            where: 'wordId = ? OR localWordId = ?',
            whereArgs: [localId, localId],
          );
        }

        // Update pending sync items
        await txn.update(
          'sync_queue',
          {'itemId': serverId.toString()},
          where: 'tableName = ? AND itemId = ? AND status = ?',
          whereArgs: [tableName, localId.toString(), 'pending'],
        );
      });
    } else if (tableName == 'sentences') {
      await db.transaction((txn) async {
        // Prefer matching the true local row by `id == localId` (offline inserts use id=localId).
        final localRowsById = await txn.query(
          'sentences',
          where: 'id = ?',
          whereArgs: [localId],
          limit: 1,
        );
        final localRows = localRowsById.isNotEmpty
            ? localRowsById
            : await txn.query(
                'sentences',
                where: 'localId = ?',
                whereArgs: [localId],
                limit: 1,
              );
        final serverRows = await txn.query(
          'sentences',
          where: 'id = ?',
          whereArgs: [serverId],
          limit: 1,
        );

        if (serverRows.isNotEmpty && localRows.isNotEmpty) {
          // Merge: keep server row id, attach localId/localWordId/createdAt if missing, remove local row.
          final serverRow = serverRows.first;
          final localRow = localRows.first;

          final serverLocalId = _toNullableInt(serverRow['localId']);
          final serverLocalWordId = _toNullableInt(serverRow['localWordId']);
          final serverCreatedAt = serverRow['createdAt']?.toString();

          final localLocalId = _toNullableInt(localRow['localId']);
          final localLocalWordId = _toNullableInt(localRow['localWordId']);
          final localCreatedAt = localRow['createdAt']?.toString();

          final updates = <String, dynamic>{
            'syncStatus': 'synced',
          };
          if (serverLocalId == null && localLocalId != null) {
            updates['localId'] = localLocalId;
          } else if (serverLocalId == null) {
            updates['localId'] = localId;
          }
          if (serverLocalWordId == null && localLocalWordId != null) {
            updates['localWordId'] = localLocalWordId;
          }
          // Prefer local createdAt (true creation time) when available.
          if (localCreatedAt != null && localCreatedAt.isNotEmpty) {
            if (serverCreatedAt == null || serverCreatedAt.isEmpty) {
              updates['createdAt'] = localCreatedAt;
            } else {
              updates['createdAt'] = localCreatedAt;
            }
          }

          if (updates.length > 1) {
            await txn.update(
              'sentences',
              updates,
              where: 'id = ?',
              whereArgs: [serverId],
            );
          }

          // Remove local row (old negative id).
          final localRowId = _toNullableInt(localRow['id']) ?? localId;
          if (localRowId != serverId) {
            await txn.delete(
              'sentences',
              where: 'id = ?',
              whereArgs: [localRowId],
            );
          }
        } else if (serverRows.isNotEmpty) {
          // Only the server row exists; just ensure it is marked synced and points to this localId for queries.
          final serverLocalId = _toNullableInt(serverRows.first['localId']);
          final updates = <String, dynamic>{
            'syncStatus': 'synced',
          };
          if (serverLocalId == null) {
            updates['localId'] = localId;
          }
          if (updates.length > 1) {
            await txn.update(
              'sentences',
              updates,
              where: 'id = ?',
              whereArgs: [serverId],
            );
          }
        } else {
          // No server row yet: safe to update the local row id -> serverId.
          await txn.update(
            'sentences',
            {'id': serverId, 'syncStatus': 'synced'},
            where: 'localId = ? OR id = ?',
            whereArgs: [localId, localId],
          );
        }

        // Update pending sync items
        await txn.update(
          'sync_queue',
          {'itemId': serverId.toString()},
          where: 'tableName = ? AND itemId = ? AND status = ?',
          whereArgs: [tableName, localId.toString(), 'pending'],
        );
      });
    }
  }

  /// Practice sentence local ID'sini server ID'sine günceller
  Future<void> updatePracticeSentenceId(String localId, String serverId) async {
    final db = await database;
    await db.update(
      'practice_sentences',
      {'id': serverId, 'syncStatus': 'synced'},
      where: 'id = ?',
      whereArgs: [localId],
    );

    await db.update(
      'sync_queue',
      {'itemId': serverId},
      where: 'tableName = ? AND itemId = ? AND status = ?',
      whereArgs: ['practice_sentences', localId, 'pending'],
    );
  }

  /// Negatif local wordId için sunucu tarafındaki gerçek ID'yi döndürür
  Future<int?> resolveServerWordId(int queuedWordId) async {
    final db = await database;
    final rows = await db.query(
      'words',
      columns: ['id'],
      where: 'localId = ? OR id = ?',
      whereArgs: [queuedWordId, queuedWordId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final rawId = rows.first['id'];
    final resolvedId = rawId is int
        ? rawId
        : (rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? ''));
    if (resolvedId == null || resolvedId <= 0) {
      return null;
    }
    return resolvedId;
  }

  // ==================== UTILITIES ====================

  /// Son senkronizasyon tarihleri tablosundan unique tarihleri getir
  Future<List<String>> getAllDistinctDates() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT learnedDate FROM words ORDER BY learnedDate DESC
    ''');
    return result.map((r) => r['learnedDate'] as String).toList();
  }

  /// Tarihe göre kelimeleri getir
  Future<List<Word>> getWordsByDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];

    final List<Map<String, dynamic>> wordMaps = await db.query(
      'words',
      where: 'learnedDate = ?',
      whereArgs: [dateStr],
    );

    List<Word> words = [];
    for (var wordMap in wordMaps) {
      final sentences = await db.query(
        'sentences',
        where: 'wordId = ? OR localWordId = ?',
        whereArgs: [wordMap['id'], wordMap['localId']],
        orderBy: 'createdAt DESC',
      );

      words.add(Word(
        id: wordMap['id'] ?? wordMap['localId'] ?? 0,
        englishWord: wordMap['englishWord'] ?? '',
        turkishMeaning: wordMap['turkishMeaning'] ?? '',
        learnedDate: DateTime.parse(wordMap['learnedDate']),
        notes: wordMap['notes'],
        difficulty: wordMap['difficulty'] ?? 'easy',
        sentences: sentences
            .map((s) => Sentence(
                  id: s['id'] as int? ?? s['localId'] as int? ?? 0,
                  sentence: s['sentence'] as String? ?? '',
                  translation: s['translation'] as String? ?? '',
                  wordId: wordMap['id'] ?? wordMap['localId'] ?? 0,
                  difficulty: s['difficulty'] as String?,
                  createdAt: _tryParseDateTime(s['createdAt']),
                ))
            .toList(),
      ));
    }

    return words;
  }

  /// Veritabanını temizle
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('words');
    await db.delete('sentences');
    await db.delete('practice_sentences');
    await db.delete('sync_queue');
    await db.delete('xp_history');
    // user_stats'ı sıfırla
    await db.update('user_stats', {
      'totalXp': 0,
      'lastSyncedXp': 0,
      'pendingXp': 0,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  // ==================== SYNC QUEUE ====================

  /// Sync queue'daki tüm bekleyen işlemleri getir
  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await database;
    return await db.query('sync_queue', orderBy: 'createdAt ASC');
  }

  /// Sync queue'dan bir item'ı sil
  Future<void> removeSyncQueueItem(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Sync queue'ya item ekle
  Future<int> addToSyncQueue(String action, String tableName, String itemId,
      Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('sync_queue', {
      'action': action,
      'tableName': tableName,
      'itemId': itemId,
      'data': jsonEncode(data),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  // ==================== XP HISTORY ====================

  Future<void> addXpHistory({
    required String actionId,
    required String actionName,
    required int amount,
    String? source,
  }) async {
    final db = await database;
    await db.insert('xp_history', {
      'actionId': actionId,
      'actionName': actionName,
      'amount': amount,
      'source': source,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getXpHistory({int limit = 200}) async {
    final db = await database;
    return await db.query(
      'xp_history',
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }
}
