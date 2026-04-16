import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/word.dart';
import '../models/sentence_practice.dart';
import 'local_database_service.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Offline/Online durumu yönetir ve senkronizasyon işlemlerini gerçekleştirir
class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  static bool _forceTestMode = false;
  @visibleForTesting
  static void enableTestMode() {
    _forceTestMode = true;
    _instance._connectivity = _TestConnectivity();
  }

  final LocalDatabaseService _localDb = LocalDatabaseService();
  ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  Connectivity _connectivity = Connectivity();

  /// Test için bağımlılıkları dışarıdan ver
  @visibleForTesting
  void setDependenciesForTesting(
      {ApiService? apiService, Connectivity? connectivity}) {
    if (apiService != null) _apiService = apiService;
    if (connectivity != null) _connectivity = connectivity;
  }

  /// Test için durumu sıfırla
  @visibleForTesting
  void resetStatusForTesting() {
    _isOnline = true;
    _isSyncing = false;
    _isCheckingConnectivity = false;
    _lastConnectivityCheck = null; // Testler gerçek check'i tetiklesin
  }

  bool _isOnline = true;

  bool _isSyncing = false;
  bool _isCheckingConnectivity = false; // Paralel kontrolleri engelle
  DateTime? _lastConnectivityCheck; // Son kontrol zamanı
  static const Duration _connectivityCacheDuration =
      Duration(minutes: 2); // 2 dakika cache - daha az kontrol
  static const int _maxSyncRetries = 5;
  static const Duration _retryBaseDelay = Duration(seconds: 30);
  static const Duration _retryMaxDelay = Duration(minutes: 15);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final StreamController<bool> _onlineStatusController =
      StreamController<bool>.broadcast();

  /// Online durumu stream
  Stream<bool> get onlineStatus => _onlineStatusController.stream;

  /// Anlık online durumu
  bool get isOnline => _isOnline;

  /// Sync queue ve bağlantı durumu için özet sağlık verisi döndürür.
  Future<Map<String, dynamic>> getSyncQueueHealth() async {
    await _checkConnectivity();
    final snapshot = await _localDb.getSyncQueueHealthSnapshot();
    return <String, dynamic>{
      ...snapshot,
      'isOnline': _isOnline,
      'isSyncing': _isSyncing,
    };
  }

  /// Servisi başlat
  Future<void> initialize() async {
    // İlk durum kontrolü
    await _checkConnectivity(force: true);

    // Bağlantı değişikliklerini dinle
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) async {
      final wasOnline = _isOnline;
      final hasNetwork = !result.contains(ConnectivityResult.none);

      // Ağ durumu değiştiyse kontrol et
      if (hasNetwork != _isOnline || !hasNetwork) {
        _isOnline = hasNetwork;
        _onlineStatusController.add(_isOnline);

        // Offline'dan online'a geçtiyse senkronize et
        if (!wasOnline && _isOnline) {
          debugPrint('📶 Bağlantı geri geldi, senkronizasyon başlatılıyor...');
          await syncWithServer();
        }
      }
    });
  }

  /// Bağlantı durumunu kontrol et (cache'li)
  Future<bool> _checkConnectivity({bool force = false}) async {
    // Eğer zaten kontrol yapılıyorsa bekle
    if (_isCheckingConnectivity) {
      return _isOnline;
    }

    // Cache süresi dolmadıysa mevcut durumu döndür
    if (!force && _lastConnectivityCheck != null) {
      final elapsed = DateTime.now().difference(_lastConnectivityCheck!);
      if (elapsed < _connectivityCacheDuration) {
        return _isOnline;
      }
    }

    _isCheckingConnectivity = true;

    try {
      final result = await _connectivity.checkConnectivity();
      final hasNetwork = !result.contains(ConnectivityResult.none);
      final isTest =
          _forceTestMode || const bool.fromEnvironment('FLUTTER_TEST');

      if (!hasNetwork) {
        _isOnline = false;
        _lastConnectivityCheck = DateTime.now();
        _onlineStatusController.add(_isOnline);
        _isCheckingConnectivity = false;
        return false;
      }

      // Test ortamında gerçek HTTP ping yapma
      if (isTest) {
        _isOnline = true;
        _lastConnectivityCheck = DateTime.now();
        _onlineStatusController.add(_isOnline);
        _isCheckingConnectivity = false;
        return true;
      }

      // API erişim kontrolü (words endpoint auth header gerektirdiği için health kullan)
      try {
        final baseUrl = await AppConfig.baseUrl;
        final response = await http
            .get(
              Uri.parse('$baseUrl/actuator/health'),
            )
            .timeout(const Duration(seconds: 5));

        _isOnline = response.statusCode == 200;
      } catch (e) {
        // API erişilemeyen durumda offline gibi davran ama sessizce
        _isOnline = false;
      }

      _lastConnectivityCheck = DateTime.now();
      _onlineStatusController.add(_isOnline);
      _isCheckingConnectivity = false;
      return _isOnline;
    } catch (e) {
      _isOnline = false;
      _lastConnectivityCheck = DateTime.now();
      _onlineStatusController.add(_isOnline);
      _isCheckingConnectivity = false;
      return false;
    }
  }

  Future<bool> _hasAuthenticatedUser() async {
    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      return false;
    }
    final userId = await _authService.getUserId();
    return userId != null && userId > 0;
  }

  /// Servisi durdur
  void dispose() {
    _connectivitySubscription?.cancel();
    _onlineStatusController.close();
  }

  // ==================== WORDS ====================

  /// Tüm kelimeleri getir - LOCAL FIRST yaklaşımı
  /// Önce local DB'den anında veriler döner, arka planda API sync yapılır
  Future<List<Word>> getAllWords() async {
    // 🚀 LOCAL FIRST: Önce local'den hemen döndür
    final localWords = await _localDb.getAllWords();

    if (localWords.isNotEmpty) {
      // Background self-heal: clean up duplicate sentence rows without blocking UI.
      Future(() async {
        for (final w in localWords) {
          if (w.sentences.length <= 1) continue;
          try {
            await _localDb.cleanupDuplicateSentencesForWord(w.id);
          } catch (_) {}
        }
      });

      // Local veri varsa hemen döndür, arka planda sync yap
      _syncWordsInBackground();
      return localWords;
    }

    // Local boşsa, connectivity check yap ve API'den çek
    await _checkConnectivity();

    if (_isOnline) {
      if (!await _hasAuthenticatedUser()) {
        return [];
      }
      try {
        final words = await _apiService.getAllWords();
        if (words.isNotEmpty) {
          await _localDb.saveAllWords(words);
          for (final w in words) {
            await _localDb.cleanupDuplicateSentencesForWord(w.id);
          }
        }
        return words;
      } catch (e) {
        debugPrint('🔴 API hatası: $e');
        return [];
      }
    }

    return [];
  }

  /// 🚀 HIZLI: Sadece local veritabanından kelimeleri al (API çağrısı yok)
  Future<List<Word>> getLocalWords() async {
    return await _localDb.getAllWords();
  }

  /// 🚀 HIZLI: Sadece local veritabanından practice sentences al (API çağrısı yok)
  Future<List<SentencePractice>> getLocalSentences() async {
    return await _localDb.getAllPracticeSentences();
  }

  /// Kelimenin lokaldeki güncel cümle sayısını döndürür (stale ID fallback dahil)
  Future<int> getSentenceCountForWord(int wordId) async {
    final words = await _localDb.getAllWords();
    int uniqueCountFor(Word word) {
      final seen = <String>{};
      for (final sentence in word.sentences) {
        final key = _normalizeComparableText(sentence.sentence);
        if (key.isEmpty) continue;
        seen.add(key);
      }
      return seen.length;
    }

    try {
      return uniqueCountFor(words.firstWhere((w) => w.id == wordId));
    } catch (_) {
      if (wordId < 0) {
        final resolvedWordId = await _resolveServerWordId(wordId);
        if (resolvedWordId != null && resolvedWordId > 0) {
          try {
            return uniqueCountFor(words.firstWhere((w) => w.id == resolvedWordId));
          } catch (_) {
            return 0;
          }
        }
      }
      return 0;
    }
  }

  /// Bekleyen değişiklikleri API'ye gönder
  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      await _checkConnectivity();
      if (_isOnline) {
        if (!await _hasAuthenticatedUser()) {
          return;
        }
        await _logSyncQueueHealth('before');
        // Sync queue'daki bekleyen işlemleri gönder
        await _processSyncQueue();
        await _logSyncQueueHealth('after');
        // API'den güncel verileri çek
        _syncWordsInBackground();
        // Not: Sentences API sync henüz implementasyonda değil
      }
    } catch (e) {
      debugPrint('🔄 Sync pending changes error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync queue'daki işlemleri işle
  Future<void> _processSyncQueue() async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null || userId <= 0) {
        debugPrint('Sync queue skipped: missing authenticated user context');
        return;
      }
      final queue = await _localDb.getRetryableSyncItems();
      final prioritizedQueue = [...queue]
        ..sort((a, b) => _syncPriority(a).compareTo(_syncPriority(b)));
      for (var item in prioritizedQueue) {
        try {
          // Her bir işlemi API'ye gönder
          await _processSyncItem(item);
          // Başarılıysa queue'dan sil
          await _localDb.removeSyncQueueItem(item['id']);
        } catch (e) {
          await _handleSyncQueueFailure(item, e);
        }
      }
    } catch (e) {
      debugPrint('Process sync queue error: $e');
    }
  }

  Future<void> _logSyncQueueHealth(String phase) async {
    try {
      final snapshot = await _localDb.getSyncQueueHealthSnapshot();
      final payload = <String, dynamic>{
        ...snapshot,
        'isOnline': _isOnline,
        'isSyncing': _isSyncing,
      };
      debugPrint('SYNC_QUEUE_HEALTH[$phase]: ${jsonEncode(payload)}');
    } catch (e) {
      debugPrint('SYNC_QUEUE_HEALTH[$phase] log error: $e');
    }
  }

  Future<void> _handleSyncQueueFailure(
    Map<String, dynamic> item,
    Object error,
  ) async {
    final queueId = _parseIntFlexible(item['id']);
    if (queueId == null) {
      return;
    }

    final retryCount = _parseIntFlexible(item['retryCount']) ?? 0;
    final nextRetryCount = retryCount + 1;
    final errorMessage = error.toString();
    final unrecoverable = _isUnrecoverableSyncError(error);
    final deferred = _isDeferredSyncError(error);
    final deadLetter = unrecoverable || nextRetryCount >= _maxSyncRetries;
    final nextRetryAt = deadLetter
        ? null
        : DateTime.now().add(_retryDelayFor(nextRetryCount, deferred));

    await _localDb.markSyncItemFailed(
      queueId,
      retryCount: nextRetryCount,
      lastError: errorMessage,
      nextRetryAt: nextRetryAt,
      deadLetter: deadLetter,
    );

    if (deadLetter) {
      debugPrint(
          'SYNC_QUEUE dead-letter id=$queueId retries=$nextRetryCount error=$errorMessage');
    } else {
      debugPrint(
        'Sync item error id=$queueId retry=$nextRetryCount'
        ' nextRetryAt=${nextRetryAt?.toIso8601String()}'
        ' deferred=$deferred error=$errorMessage',
      );
    }
  }

  Duration _retryDelayFor(int retryCount, bool deferred) {
    final exponent = retryCount.clamp(1, 10) - 1;
    final multiplier = 1 << exponent;
    final base = deferred ? const Duration(seconds: 10) : _retryBaseDelay;
    final delay = Duration(seconds: base.inSeconds * multiplier);
    if (delay > _retryMaxDelay) {
      return _retryMaxDelay;
    }
    return delay;
  }

  /// Tek bir sync item'ı işle
  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    final action = item['action']?.toString();
    final tableName = item['tableName']?.toString();
    final itemId = _parseIntFlexible(item['itemId']);
    final rawItemId = item['itemId']?.toString() ?? '';
    final rawData = item['data'];
    Map<String, dynamic> data = {};
    if (rawData is String && rawData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        data = {};
      }
    } else if (rawData is Map<String, dynamic>) {
      data = rawData;
    } else if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    }

    switch (action) {
      case 'create':
        if (tableName == 'words') {
          final english =
              _firstNonEmpty([data['english'], data['englishWord']]);
          final turkish =
              _firstNonEmpty([data['turkish'], data['turkishMeaning']]);
          final addedDate = _tryParseDate(
              [data['addedDate'], data['learnedDate'], data['createdDate']]);
          if (english.isEmpty || turkish.isEmpty || addedDate == null) {
            throw StateError('Invalid queued word payload');
          }

          final serverWord = await _apiService.createWord(
            english: english,
            turkish: turkish,
            addedDate: addedDate,
            difficulty: data['difficulty']?.toString() ?? 'easy',
          );
          if (itemId != null && itemId < 0) {
            await _localDb.updateLocalIdToServerId(
                'words', itemId, serverWord.id);
          }
          await _localDb.saveWord(serverWord);
        } else if (tableName == 'sentences') {
          final queuedWordId = _parseIntFlexible(data['wordId']) ??
              _parseIntFlexible(data['localWordId']) ??
              _parseIntFlexible(data['parentWordId']);
          if (queuedWordId == null) {
            throw StateError('Missing queued sentence wordId');
          }

          final resolvedWordId = await _resolveServerWordId(queuedWordId);
          if (resolvedWordId == null || resolvedWordId <= 0) {
            throw StateError('Queued sentence waiting for parent word sync');
          }

          final sentenceText =
              _firstNonEmpty([data['sentence'], data['englishSentence']]);
          final translationText =
              _firstNonEmpty([data['translation'], data['turkishTranslation']]);
          if (sentenceText.isEmpty || translationText.isEmpty) {
            throw StateError('Invalid queued sentence payload');
          }
          final serverWord = await _apiService.addSentenceToWord(
            wordId: resolvedWordId,
            sentence: sentenceText,
            translation: translationText,
            difficulty: data['difficulty']?.toString() ?? 'easy',
          );
          final matchedServerSentenceId = _findServerSentenceId(
            serverWord: serverWord,
            sentence: sentenceText,
            translation: translationText,
          );
          if (itemId != null && itemId < 0 && matchedServerSentenceId != null) {
            await _localDb.updateLocalIdToServerId(
                'sentences', itemId, matchedServerSentenceId);
          }
          await _localDb.saveWord(serverWord);
          await _localDb.cleanupDuplicateSentencesForWord(resolvedWordId);
        } else if (tableName == 'practice_sentences') {
          final englishSentence =
              _firstNonEmpty([data['englishSentence'], data['sentence']]);
          final turkishTranslation =
              _firstNonEmpty([data['turkishTranslation'], data['translation']]);
          if (englishSentence.isEmpty) {
            throw StateError('Invalid queued practice sentence payload');
          }

          final serverSentence = await _apiService.createSentence(
            englishSentence: englishSentence,
            turkishTranslation: turkishTranslation,
            difficulty: data['difficulty']?.toString() ?? 'easy',
          );

          if (rawItemId.isNotEmpty) {
            await _localDb.updatePracticeSentenceId(
                rawItemId, serverSentence.id);
          }
          await _localDb.savePracticeSentence(serverSentence);
        }
        break;
      case 'delete':
        if (tableName == 'words') {
          if (itemId == null || itemId <= 0) {
            return;
          }
          await _apiService.deleteWord(itemId);
        } else if (tableName == 'sentences') {
          if (itemId == null || itemId <= 0) {
            return;
          }
          final queuedWordId = _parseIntFlexible(data['wordId']) ??
              _parseIntFlexible(data['localWordId']) ??
              _parseIntFlexible(data['parentWordId']);
          if (queuedWordId == null) {
            return;
          }
          final resolvedWordId = await _resolveServerWordId(queuedWordId);
          if (resolvedWordId == null || resolvedWordId <= 0) {
            throw StateError(
                'Queued sentence delete waiting for parent word sync');
          }
          await _apiService.deleteSentenceFromWord(
            resolvedWordId,
            itemId,
          );
        } else if (tableName == 'practice_sentences') {
          if (rawItemId.isEmpty) {
            return;
          }
          final apiId = rawItemId.replaceFirst('practice_', '');
          await _apiService.deleteSentence(apiId);
        }
        break;
    }
  }

  Future<int?> _resolveServerWordId(int queuedWordId) async {
    if (queuedWordId > 0) {
      return queuedWordId;
    }
    return await _localDb.resolveServerWordId(queuedWordId);
  }

  String _normalizeComparableText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();
  }

  int? _findServerSentenceId({
    required Word serverWord,
    required String sentence,
    required String translation,
  }) {
    final targetSentence = _normalizeComparableText(sentence);
    final targetTranslation = _normalizeComparableText(translation);
    if (targetSentence.isEmpty) {
      return null;
    }

    final candidates = serverWord.sentences
        .where((s) =>
            s.id > 0 &&
            _normalizeComparableText(s.sentence) == targetSentence)
        .toList();
    if (candidates.isEmpty) {
      return null;
    }

    int scoreFor(Sentence s) {
      final normalizedTranslation = _normalizeComparableText(s.translation);
      if (targetTranslation.isEmpty) {
        return normalizedTranslation.isEmpty ? 1 : 0;
      }
      if (normalizedTranslation == targetTranslation) {
        return 3;
      }
      // Still allow sentence-only matching; score lower than exact translation match.
      return 0;
    }

    candidates.sort((a, b) {
      final scoreDiff = scoreFor(b) - scoreFor(a);
      if (scoreDiff != 0) return scoreDiff;
      return b.id.compareTo(a.id);
    });
    return candidates.first.id;
  }

  bool _isUnrecoverableSyncError(Object error) {
    final message = error.toString();
    return message.contains('Invalid queued word payload') ||
        message.contains('Invalid queued sentence payload') ||
        message.contains('Invalid queued practice sentence payload') ||
        message.contains('Missing queued sentence wordId');
  }

  bool _isDeferredSyncError(Object error) {
    final message = error.toString();
    return message.contains('Queued sentence waiting for parent word sync') ||
        message.contains('Queued sentence delete waiting for parent word sync');
  }

  int _syncPriority(Map<String, dynamic> item) {
    final action = item['action']?.toString() ?? '';
    final tableName = item['tableName']?.toString() ?? '';
    if (action == 'create' && tableName == 'words') return 0;
    if (action == 'create' && tableName == 'sentences') return 1;
    if (action == 'create' && tableName == 'practice_sentences') return 2;
    if (action == 'delete' && tableName == 'sentences') return 3;
    if (action == 'delete' && tableName == 'practice_sentences') return 4;
    if (action == 'delete' && tableName == 'words') return 5;
    return 10;
  }

  int? _parseIntFlexible(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    final direct = int.tryParse(raw);
    if (direct != null) {
      return direct;
    }
    final match = RegExp(r'-?\d+').firstMatch(raw);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!);
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final normalized = value?.toString().trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  DateTime? _tryParseDate(List<dynamic> values) {
    for (final value in values) {
      final normalized = value?.toString().trim() ?? '';
      if (normalized.isEmpty) {
        continue;
      }
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// Arka planda API'den kelimeleri sync et (UI'ı bloklamaz)
  void _syncWordsInBackground() {
    if (_forceTestMode || const bool.fromEnvironment('FLUTTER_TEST')) return;
    // Fire and forget - arka planda çalışır
    Future(() async {
      try {
        if (!await _hasAuthenticatedUser()) {
          return;
        }
        if (!_isOnline) {
          await _checkConnectivity();
        }
        if (_isOnline) {
          final words = await _apiService.getAllWords();
          if (words.isNotEmpty) {
            await _localDb.saveAllWords(words);
            for (final w in words) {
              await _localDb.cleanupDuplicateSentencesForWord(w.id);
            }
          }
        }
      } catch (e) {
        // Sessizce hata logla
        debugPrint('🔄 Background sync error: $e');
      }
    });
  }

  /// Kelime oluştur - OPTIMISTIC UPDATE
  /// Önce local'e kaydet (anında görünsün), sonra arka planda API'ye gönder
  Future<Word?> createWord({
    required String english,
    required String turkish,
    required DateTime addedDate,
    String difficulty = 'easy',
  }) async {
    // 🚀 OPTIMISTIC UPDATE: Önce local'e kaydet ve hemen döndür
    final localId = await _localDb.createWordOffline(
      english: english,
      turkish: turkish,
      addedDate: addedDate,
      difficulty: difficulty,
    );

    final localWord = Word(
      id: localId,
      englishWord: english,
      turkishMeaning: turkish,
      learnedDate: addedDate,
      difficulty: difficulty,
      sentences: [],
    );

    // Test ortamında senkronizasyonu inline yap (deterministik)
    final isTest = _forceTestMode || const bool.fromEnvironment('FLUTTER_TEST');
    if (isTest) {
      final result = await _connectivity.checkConnectivity();
      final hasNetwork = !result.contains(ConnectivityResult.none);
      if (hasNetwork) {
        await _syncWordToAPIWithoutConnectivityCheck(localWord);
      }
    } else {
      // Arka planda API'ye gönder (UI'ı bloklamaz)
      _syncWordToAPIInBackground(localWord);
    }

    return localWord;
  }

  /// Arka planda kelimeyi API'ye sync et
  void _syncWordToAPIInBackground(Word localWord) {
    Future(() async {
      await _syncWordToAPI(localWord);
    });
  }

  Future<void> _syncWordToAPI(Word localWord) async {
    try {
      await _checkConnectivity();
      if (_isOnline) {
        final serverWord = await _apiService.createWord(
          english: localWord.englishWord,
          turkish: localWord.turkishMeaning,
          addedDate: localWord.learnedDate,
          difficulty: localWord.difficulty,
        );

        // BAŞARILI: Sync queue'dan bu işlemi sil (ID'ler güncellenmeden önce yap)
        final queue = await _localDb.getSyncQueue();
        final item = queue.firstWhere(
          (q) =>
              q['tableName'] == 'words' &&
              q['itemId'] == localWord.id.toString() &&
              q['action'] == 'create',
          orElse: () => <String, dynamic>{},
        );

        if (item.isNotEmpty) {
          await _localDb.removeSyncQueueItem(item['id']);
        }

        // Şimdi yerel veritabanındaki ID'leri güncelle
        await _localDb.updateLocalIdToServerId(
            'words', localWord.id, serverWord.id);
        debugPrint(
          '🧭 word sync mapped: localWordId=${localWord.id} -> serverWordId=${serverWord.id}',
        );
        await _localDb.saveWord(serverWord);
      }
      // else: Offline ise queue'da zaten var (createWordOffline ekledi)
    } catch (e) {
      debugPrint('🔄 Background word sync error: $e');
      // Hata durumunda queue'da zaten var, bir şey yapmaya gerek yok
    }
  }

  Future<void> _syncWordToAPIWithoutConnectivityCheck(Word localWord) async {
    try {
      final serverWord = await _apiService.createWord(
        english: localWord.englishWord,
        turkish: localWord.turkishMeaning,
        addedDate: localWord.learnedDate,
        difficulty: localWord.difficulty,
      );

      final queue = await _localDb.getSyncQueue();
      final item = queue.firstWhere(
        (q) =>
            q['tableName'] == 'words' &&
            q['itemId'] == localWord.id.toString() &&
            q['action'] == 'create',
        orElse: () => <String, dynamic>{},
      );

      if (item.isNotEmpty) {
        await _localDb.removeSyncQueueItem(item['id']);
      }

      await _localDb.updateLocalIdToServerId(
          'words', localWord.id, serverWord.id);
      debugPrint(
        '🧭 word sync mapped: localWordId=${localWord.id} -> serverWordId=${serverWord.id}',
      );
      await _localDb.saveWord(serverWord);
    } catch (e) {
      debugPrint('🔄 Background word sync error: $e');
    }
  }

  /// Kelime sil - OPTIMISTIC UPDATE
  /// Önce local'den sil (anında görünsün), sonra arka planda API'ye gönder
  Future<bool> deleteWord(int wordId) async {
    final resolvedWordId = wordId > 0 ? wordId : await _resolveServerWordId(wordId);

    // 🚀 OPTIMISTIC UPDATE: Önce local'den sil ve hemen dön
    int deletedWords = await _localDb.deleteWord(wordId);
    if (resolvedWordId != null && resolvedWordId != wordId) {
      deletedWords += await _localDb.deleteWord(resolvedWordId);
    }
    if (deletedWords <= 0) {
      return false;
    }

    // Queue temizliği: silinen kelimeye ait bekleyen word/sentence işlemlerini temizle
    final candidateWordIds = <int>{wordId};
    if (resolvedWordId != null) {
      candidateWordIds.add(resolvedWordId);
    }
    for (final candidateId in candidateWordIds) {
      await _removeQueuedWordCreate(candidateId);
      await _removeQueuedWordDelete(candidateId);
    }
    await _removeQueuedSentenceItemsForWords(candidateWordIds);

    // Server'da var olabilecek kelimeler için silme çağrısını başlat
    final targetWordId = resolvedWordId ?? wordId;
    if (targetWordId > 0) {
      _deleteWordFromAPIInBackground(targetWordId);
    }

    return true;
  }

  /// Arka planda kelimeyi API'den sil
  void _deleteWordFromAPIInBackground(int wordId) {
    if (wordId <= 0) {
      return; // Negatif ID'ler (local-only) için API çağrısı yapma
    }

    Future(() async {
      try {
        await _checkConnectivity();
        if (_isOnline) {
          await _apiService.deleteWord(wordId);
          await _removeQueuedWordDelete(wordId);
        } else {
          await _queueWordDeleteIfNeeded(wordId);
        }
      } catch (e) {
        debugPrint('🔄 Background word delete error: $e');
        await _queueWordDeleteIfNeeded(wordId);
      }
    });
  }

  /// Kelimeye cümle ekle - OPTIMISTIC UPDATE
  /// Önce local'e kaydet (anında görünsün), sonra arka planda API'ye gönder
  Future<Word?> addSentenceToWord({
    required int wordId,
    required String sentence,
    required String translation,
    String difficulty = 'easy',
  }) async {
    // 🚀 OPTIMISTIC UPDATE: Önce local'e kaydet ve hemen döndür
    final sentenceId = await _localDb.addSentenceToWordOffline(
      wordId: wordId,
      sentence: sentence,
      translation: translation,
      difficulty: difficulty,
    );
    debugPrint(
      '🧭 addSentenceToWord local insert: wordId=$wordId sentenceId=$sentenceId',
    );

    // Güncel kelimeyi hemen döndür
    final updatedWord = await _getWordWithNewSentence(
        wordId, sentenceId, sentence, translation, difficulty);

    // Arka planda API'ye gönder
    _syncSentenceToAPIInBackground(
      wordId,
      sentenceId,
      sentence,
      translation,
      difficulty,
    );

    return updatedWord;
  }

  /// Arka planda cümleyi API'ye sync et
  void _syncSentenceToAPIInBackground(
    int wordId,
    int localSentenceId,
    String sentence,
    String translation,
    String difficulty,
  ) {
    if (_forceTestMode || const bool.fromEnvironment('FLUTTER_TEST')) return;

    Future(() async {
      try {
        await _checkConnectivity();
        if (_isOnline) {
          int? targetWordId =
              wordId > 0 ? wordId : await _resolveServerWordId(wordId);
          if (targetWordId == null || targetWordId <= 0) {
            return;
          }
          final word = await _apiService.addSentenceToWord(
            wordId: targetWordId,
            sentence: sentence,
            translation: translation,
            difficulty: difficulty,
          );
          final matchedServerSentenceId = _findServerSentenceId(
            serverWord: word,
            sentence: sentence,
            translation: translation,
          );
          if (matchedServerSentenceId != null && localSentenceId < 0) {
            await _removeQueuedSentenceCreate(localSentenceId);
            await _localDb.updateLocalIdToServerId(
              'sentences',
              localSentenceId,
              matchedServerSentenceId,
            );
          }
          await _localDb.saveWord(word);
          await _localDb.cleanupDuplicateSentencesForWord(targetWordId);
        }
      } catch (e) {
        debugPrint('🔄 Background sentence sync error: $e');
      }
    });
  }

  /// Yeni cümle eklenmiş kelimeyi döndür (offline durumlar için helper)
  Future<Word?> _getWordWithNewSentence(int wordId, int sentenceId,
      String sentence, String translation, String difficulty) async {
    try {
      // Veritabanı zaten cümleyi içeriyor (addSentenceToWordOffline ile eklendi)
      // Güncel kelimeyi veritabanından al ve döndür
      final words = await _localDb.getAllWords();
      Word? word;
      try {
        word = words.firstWhere((w) => w.id == wordId);
      } catch (_) {
        word = null;
      }

      // UI'daki local(-) wordId arka planda server(+) id'ye dönmüş olabilir.
      if (word == null && wordId < 0) {
        final resolvedWordId = await _resolveServerWordId(wordId);
        debugPrint(
          '🧭 _getWordWithNewSentence resolve: localWordId=$wordId resolvedWordId=$resolvedWordId',
        );
        if (resolvedWordId != null && resolvedWordId > 0) {
          try {
            word = words.firstWhere((w) => w.id == resolvedWordId);
          } catch (_) {
            word = null;
          }
        }
      }

      return word; // Cümle zaten veritabanından alındı, tekrar eklemeye gerek yok
    } catch (e) {
      debugPrint('Error getting word with new sentence: $e');
      return null;
    }
  }

  /// Kelimeden cümle sil
  Future<bool> deleteSentenceFromWord({
    required int wordId,
    required int sentenceId,
  }) async {
    await _checkConnectivity();
    final hasAuthUser = await _hasAuthenticatedUser();
    final resolvedWordId =
        wordId > 0 ? wordId : await _resolveServerWordId(wordId);

    String branchReason = 'server-delete';
    if (sentenceId <= 0) {
      branchReason = 'local-temp-id';
    } else if (!_isOnline) {
      branchReason = 'no-network';
    } else if (!hasAuthUser) {
      branchReason = 'missing-auth-context';
    } else if (resolvedWordId == null || resolvedWordId <= 0) {
      branchReason = 'pending-parent-word';
    }
    debugPrint(
      '🧭 deleteSentenceFromWord context: online=$_isOnline auth=$hasAuthUser '
      'wordId=$wordId sentenceId=$sentenceId reason=$branchReason',
    );

    if (sentenceId <= 0) {
      // Local-only cümleler için server delete kuyruğuna gerek yok.
      final deletedRows = await _deleteSentenceFromLocal(
        requestedWordId: wordId,
        resolvedWordId: resolvedWordId,
        sentenceId: sentenceId,
      );
      if (deletedRows <= 0) {
        return false;
      }
      await _removeQueuedSentenceCreate(sentenceId);
      await _removeQueuedSentenceDelete(sentenceId);
      return true;
    }

    if (_isOnline &&
        hasAuthUser &&
        resolvedWordId != null &&
        resolvedWordId > 0) {
      try {
        // Online: API'den sil
        await _apiService.deleteSentenceFromWord(resolvedWordId, sentenceId);
        // Local'den de sil
        final deletedRows = await _deleteSentenceFromLocal(
          requestedWordId: wordId,
          resolvedWordId: resolvedWordId,
          sentenceId: sentenceId,
        );
        if (deletedRows <= 0) {
          return false;
        }
        final stillOnServer = await _isSentenceStillPresentOnServer(sentenceId);
        if (stillOnServer) {
          // If the server still serves this sentence (e.g. stale wordId / backend mismatch),
          // keep a tombstone delete in queue so refreshes cannot resurrect it locally.
          await _queueSentenceDeleteIfNeeded(
            wordId: resolvedWordId,
            sentenceId: sentenceId,
          );
        } else {
          await _removeQueuedSentenceDelete(sentenceId);
        }
        return true;
      } catch (e) {
        debugPrint('🔴 API hatası, offline silme yapılıyor: $e');
        final deletedRows = await _deleteSentenceFromLocal(
          requestedWordId: wordId,
          resolvedWordId: resolvedWordId,
          sentenceId: sentenceId,
        );
        if (deletedRows <= 0) {
          return false;
        }
        await _queueSentenceDeleteIfNeeded(
          wordId: resolvedWordId,
          sentenceId: sentenceId,
        );
        return true;
      }
    } else {
      // Offline: Local veritabanından sil ve sync queue'ya ekle
      debugPrint('📴 Offline mod: Cümle lokal siliniyor');
      final deletedRows = await _deleteSentenceFromLocal(
        requestedWordId: wordId,
        resolvedWordId: resolvedWordId,
        sentenceId: sentenceId,
      );
      if (deletedRows <= 0) {
        return false;
      }
      await _queueSentenceDeleteIfNeeded(
        wordId: resolvedWordId ?? wordId,
        sentenceId: sentenceId,
      );
      return true;
    }
  }

  Future<bool> _isSentenceStillPresentOnServer(int sentenceId) async {
    try {
      final serverWords = await _apiService.getAllWords();
      for (final word in serverWords) {
        if (word.sentences.any((s) => s.id == sentenceId)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint(
        '⚠️ Server sentence doğrulaması başarısız '
        '(sentenceId=$sentenceId): $e',
      );
      // Conservatively assume it may still exist so tombstone behavior remains safe.
      return true;
    }
  }

  Future<int> _deleteSentenceFromLocal({
    required int requestedWordId,
    required int? resolvedWordId,
    required int sentenceId,
  }) async {
    int deleted = await _localDb.deleteSentenceFromWord(requestedWordId, sentenceId);
    if (resolvedWordId != null && resolvedWordId != requestedWordId) {
      deleted += await _localDb.deleteSentenceFromWord(resolvedWordId, sentenceId);
    }
    return deleted;
  }

  Future<void> _queueSentenceDeleteIfNeeded({
    required int wordId,
    required int sentenceId,
  }) async {
    final queue = await _localDb.getSyncQueue();
    final alreadyQueued = queue.any((item) {
      return item['tableName']?.toString() == 'sentences' &&
          item['action']?.toString() == 'delete' &&
          item['itemId']?.toString() == sentenceId.toString();
    });
    if (!alreadyQueued) {
      await _localDb.addToSyncQueue(
        'delete',
        'sentences',
        sentenceId.toString(),
        {'wordId': wordId},
      );
    }
  }

  Future<void> _removeQueuedSentenceCreate(int sentenceId) async {
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() == 'sentences' &&
          item['action']?.toString() == 'create' &&
          item['itemId']?.toString() == sentenceId.toString()) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  Future<void> _removeQueuedSentenceDelete(int sentenceId) async {
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() == 'sentences' &&
          item['action']?.toString() == 'delete' &&
          item['itemId']?.toString() == sentenceId.toString()) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  Future<void> _queueWordDeleteIfNeeded(int wordId) async {
    if (wordId <= 0) {
      return;
    }
    final queue = await _localDb.getSyncQueue();
    final alreadyQueued = queue.any((item) {
      return item['tableName']?.toString() == 'words' &&
          item['action']?.toString() == 'delete' &&
          item['itemId']?.toString() == wordId.toString();
    });
    if (!alreadyQueued) {
      await _localDb.addToSyncQueue('delete', 'words', wordId.toString(), {});
    }
  }

  Future<void> _removeQueuedWordCreate(int wordId) async {
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() == 'words' &&
          item['action']?.toString() == 'create' &&
          item['itemId']?.toString() == wordId.toString()) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  Future<void> _removeQueuedWordDelete(int wordId) async {
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() == 'words' &&
          item['action']?.toString() == 'delete' &&
          item['itemId']?.toString() == wordId.toString()) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  Future<void> _removeQueuedSentenceItemsForWords(Set<int> wordIds) async {
    if (wordIds.isEmpty) return;
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() != 'sentences') {
        continue;
      }
      final rawData = item['data'];
      int? queuedWordId;
      if (rawData is String && rawData.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawData);
          if (decoded is Map) {
            queuedWordId = _parseIntFlexible(
                  decoded['wordId'] ?? decoded['localWordId'] ?? decoded['parentWordId'],
                ) ??
                queuedWordId;
          }
        } catch (_) {}
      }
      if (queuedWordId != null && wordIds.contains(queuedWordId)) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  // ==================== PRACTICE SENTENCES ====================

  /// Tüm practice sentences getir - LOCAL FIRST yaklaşımı
  Future<List<SentencePractice>> getAllSentences({bool forceRefresh = false}) async {
    // Always read local first for quick UI.
    final localSentences = await _localDb.getAllPracticeSentences();

    // If the caller doesn't need server truth, keep the original local-first behavior.
    if (!forceRefresh) {
      if (localSentences.isNotEmpty) {
        _syncSentencesInBackground();
        return localSentences;
      }
    }

    // If forced (or local empty), try to refresh from server when online.
    await _checkConnectivity();

    if (_isOnline) {
      if (!await _hasAuthenticatedUser()) {
        return localSentences;
      }
      try {
        final sentences = await _apiService.getAllSentences();
        final practiceOnly = sentences.where((s) => s.source == 'practice').toList();

        // Important: always reconcile local cache against server truth, even if empty.
        await _localDb.saveAllPracticeSentences(practiceOnly);
        return practiceOnly;
      } catch (e) {
        debugPrint('🔴 API hatası: $e');
        return localSentences;
      }
    }

    return localSentences;
  }

  /// Arka planda API'den cümleleri sync et
  void _syncSentencesInBackground() {
    if (_forceTestMode || const bool.fromEnvironment('FLUTTER_TEST')) return;
    Future(() async {
      try {
        if (!await _hasAuthenticatedUser()) {
          return;
        }
        if (!_isOnline) await _checkConnectivity();
        if (_isOnline) {
          final sentences = await _apiService.getAllSentences();
          final practiceOnly =
              sentences.where((s) => s.source == 'practice').toList();

          // Reconcile local cache even when server has no practice sentences.
          await _localDb.saveAllPracticeSentences(practiceOnly);
        }
      } catch (e) {
        debugPrint('🔄 Background sentences sync error: $e');
      }
    });
  }

  /// Practice sentence oluştur
  Future<SentencePractice?> createSentence({
    required String englishSentence,
    required String turkishTranslation,
    required String difficulty,
  }) async {
    await _checkConnectivity();

    if (_isOnline) {
      try {
        final sentence = await _apiService.createSentence(
          englishSentence: englishSentence,
          turkishTranslation: turkishTranslation,
          difficulty: difficulty,
        );
        await _localDb.savePracticeSentence(sentence);
        // XP artık AppStateProvider tarafından yönetiliyor
        return sentence;
      } catch (e) {
        debugPrint('🔴 API hatası, offline kayıt yapılıyor: $e');
        final id = await _localDb.createPracticeSentenceOffline(
          englishSentence: englishSentence,
          turkishTranslation: turkishTranslation,
          difficulty: difficulty,
        );
        return SentencePractice(
          id: id,
          englishSentence: englishSentence,
          turkishTranslation: turkishTranslation,
          difficulty: difficulty.toUpperCase(),
          createdDate: DateTime.now(),
          source: 'practice',
        );
      }
    } else {
      debugPrint('📴 Offline mod: Cümle lokal kaydediliyor');
      final id = await _localDb.createPracticeSentenceOffline(
        englishSentence: englishSentence,
        turkishTranslation: turkishTranslation,
        difficulty: difficulty,
      );
      return SentencePractice(
        id: id,
        englishSentence: englishSentence,
        turkishTranslation: turkishTranslation,
        difficulty: difficulty.toUpperCase(),
        createdDate: DateTime.now(),
        source: 'practice',
      );
    }
  }

  /// Practice sentence sil
  Future<bool> deletePracticeSentence(String id) async {
    await _checkConnectivity();

    // Sadece server ID'leri için API çağrısı yap (temp/local değilse)
    bool isServerId = !id.startsWith('temp_') && !id.startsWith('local_');

    if (_isOnline) {
      if (isServerId) {
        try {
          // 'practice_' prefix'ini kaldır
          final apiId = id.replaceFirst('practice_', '');
          await _apiService.deleteSentence(apiId);
          await _removeQueuedPracticeDelete(id);
        } catch (e) {
          debugPrint('🔴 API hatası, offline silme kuyruğa ekleniyor: $e');
          await _localDb.addToSyncQueue('delete', 'practice_sentences', id, {});
        }
      }
      // Local DB'den her durumda sil
      final deletedRows = await _localDb.deletePracticeSentence(id);
      if (!isServerId) {
        await _removeQueuedPracticeCreate(id);
      }
      return deletedRows > 0;
    } else {
      final deletedRows = await _localDb.deletePracticeSentence(id);
      if (!isServerId) {
        await _removeQueuedPracticeCreate(id);
      }
      if (isServerId) {
        await _localDb.addToSyncQueue('delete', 'practice_sentences', id, {});
      }
      return deletedRows > 0;
    }
  }

  Future<void> _removeQueuedPracticeCreate(String practiceId) async {
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() == 'practice_sentences' &&
          item['action']?.toString() == 'create' &&
          item['itemId']?.toString() == practiceId) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  Future<void> _removeQueuedPracticeDelete(String practiceId) async {
    final queue = await _localDb.getSyncQueue();
    for (final item in queue) {
      if (item['tableName']?.toString() == 'practice_sentences' &&
          item['action']?.toString() == 'delete' &&
          item['itemId']?.toString() == practiceId) {
        final queueId = _parseIntFlexible(item['id']);
        if (queueId != null) {
          await _localDb.removeSyncQueueItem(queueId);
        }
      }
    }
  }

  // ==================== DATES ====================

  /// Benzersiz tarihleri getir
  Future<List<String>> getAllDistinctDates() async {
    await _checkConnectivity();

    if (_isOnline) {
      try {
        return await _apiService.getAllDistinctDates();
      } catch (e) {
        return await _localDb.getAllDistinctDates();
      }
    } else {
      return await _localDb.getAllDistinctDates();
    }
  }

  /// Tarihe göre kelimeleri getir
  Future<List<Word>> getWordsByDate(DateTime date) async {
    await _checkConnectivity();

    if (_isOnline) {
      try {
        final words = await _apiService.getWordsByDate(date);
        return words;
      } catch (e) {
        return await _localDb.getWordsByDate(date);
      }
    } else {
      return await _localDb.getWordsByDate(date);
    }
  }

  // ==================== XP ====================

  /// Toplam XP getir (local + pending)
  Future<int> getTotalXp() async {
    return await _localDb.getTotalXp();
  }

  /// Pending XP getir
  Future<int> getPendingXp() async {
    return await _localDb.getPendingXp();
  }

  /// XP ekle (ve local DB'ye kaydet)
  Future<void> addXp(int amount) async {
    await _localDb.addXp(amount);
  }

  // ==================== SYNC ====================

  /// Sunucu ile senkronize et
  Future<bool> syncWithServer() async {
    if (_isSyncing) {
      debugPrint('⏳ Senkronizasyon zaten devam ediyor...');
      return false;
    }

    if (!_isOnline) {
      debugPrint('📴 Offline - senkronizasyon atlanıyor');
      return false;
    }
    if (!await _hasAuthenticatedUser()) {
      debugPrint('🔐 Login yok: Sunucu senkronizasyonu atlandı');
      return false;
    }

    _isSyncing = true;
    debugPrint('🔄 Senkronizasyon başlatıldı...');

    try {
      // 1. Bekleyen işlemleri gönder
      final pendingItems = await _localDb.getPendingSyncItems();
      debugPrint('📝 ${pendingItems.length} bekleyen işlem bulundu');
      await _logSyncQueueHealth('syncWithServer-before');
      await _processSyncQueue();
      await _logSyncQueueHealth('syncWithServer-after');

      // 2. Sunucudan güncel verileri al
      final serverWords = await _apiService.getAllWords();
      if (serverWords.isNotEmpty) {
        await _localDb.saveAllWords(serverWords);
      }

      final serverSentences = await _apiService.getAllSentences();
      final practiceOnly =
          serverSentences.where((s) => s.source == 'practice').toList();
      await _localDb.saveAllPracticeSentences(practiceOnly);

      // 3. XP'yi senkronize et (server XP + pending XP)
      // Not: Gerçek uygulamada server'dan XP almak gerekir
      // Şimdilik local XP'yi koruyoruz
      await _localDb.markXpSynced();

      debugPrint('✅ Senkronizasyon tamamlandı');
      _isSyncing = false;
      return true;
    } catch (e) {
      debugPrint('🔴 Senkronizasyon hatası: $e');
      _isSyncing = false;
      return false;
    }
  }

  /// İlk veri yüklemesi (uygulama başlangıcında)
  Future<void> initialDataLoad() async {
    await _checkConnectivity();

    if (_isOnline) {
      if (!await _hasAuthenticatedUser()) {
        debugPrint('🔐 Login yok: İlk veri yüklemesi sadece local modda');
        return;
      }
      try {
        // Online: Sunucudan al ve local'e kaydet
        final words = await _apiService.getAllWords();
        if (words.isNotEmpty) {
          await _localDb.saveAllWords(words);
        }

        final sentences = await _apiService.getAllSentences();
        final practiceOnly =
            sentences.where((s) => s.source == 'practice').toList();
        await _localDb.saveAllPracticeSentences(practiceOnly);

        debugPrint(
            '✅ İlk veri yüklemesi tamamlandı: ${words.length} kelime, ${sentences.length} cümle');
      } catch (e) {
        debugPrint('🔴 İlk veri yüklemesi hatası: $e');
      }
    }
  }
}

class _TestConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return [ConnectivityResult.none];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return const Stream<List<ConnectivityResult>>.empty();
  }

  Future<void> deleteService() async {}

  Future<String?> getWifiBSSID() async => null;

  Future<String?> getWifiIP() async => null;

  Future<String?> getWifiName() async => null;
}

