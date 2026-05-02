import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/offline_sync_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/xp_manager.dart';
import '../services/local_database_service.dart';
import '../models/word.dart';
import '../models/sentence_view_model.dart';
import '../services/groq_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global App State Provider - Uygulama genelinde veriyi merkezi tutar
/// Bu sayede sayfalar arası geçişte veri tekrar yüklenmez
class AppStateProvider extends ChangeNotifier {
  final OfflineSyncService _offlineSyncService = OfflineSyncService();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final XPManager _xpManager = XPManager();
  final LocalDatabaseService _localDb = LocalDatabaseService();

  AppStateProvider() {
    // XP değişikliklerini dinle ve UI'ı güncelle
    _xpManager.setOnXPChanged((totalXP, addedXP, action) {
      _userStats['xp'] = totalXP;
      _userStats['level'] = _xpManager.calculateLevel(totalXP);
      _userStats['xpToNextLevel'] = _xpManager.xpForNextLevel(totalXP);
      final currentWeeklyXP = (_userStats['weeklyXP'] as int?) ?? 0;
      final nextWeeklyXP = currentWeeklyXP + addedXP;
      _userStats['weeklyXP'] = nextWeeklyXP < 0 ? 0 : nextWeeklyXP;
      _userStats = Map<String, dynamic>.from(_userStats);
      notifyListeners();
    });
  }

  Map<String, dynamic> _buildDefaultUserStats() {
    return {
      'name': 'Kullanıcı',
      'level': 1,
      'xp': 0,
      'xpToNextLevel': 100,
      'totalWords': 0,
      'streak': 0,
      'weeklyXP': 0,
      'dailyGoal': 5,
      'learnedToday': 0,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // LOADING STATES
  // ═══════════════════════════════════════════════════════════════
  bool _isInitialized = false;
  bool _isLoadingWords = false;
  bool _isLoadingSentences = false;
  bool _isLoadingDailyWords = false;
  bool _isLoadingAiEntitlement = false;
  bool _hasResolvedAiEntitlement = false;

  bool get isInitialized => _isInitialized;
  bool get isLoadingWords => _isLoadingWords;
  bool get isLoadingSentences => _isLoadingSentences;
  bool get isLoadingDailyWords => _isLoadingDailyWords;
  bool get isLoadingAiEntitlement => _isLoadingAiEntitlement;
  bool get hasResolvedAiEntitlement => _hasResolvedAiEntitlement;

  // ═══════════════════════════════════════════════════════════════
  // USER DATA
  // ═══════════════════════════════════════════════════════════════
  String _userName = 'Kullanıcı';
  Map<String, dynamic>? _userInfo; // Full user info from auth
  late Map<String, dynamic> _userStats = _buildDefaultUserStats();
  List<Map<String, dynamic>> _weeklyActivity = [];

  // Profile
  String? _profileImageType;
  String? _profileImagePath;
  String _avatarSeed = '';

  String get userName => _userName;
  Map<String, dynamic>? get userInfo => _userInfo;
  Map<String, dynamic> get userStats => _userStats;
  List<Map<String, dynamic>> get weeklyActivity => _weeklyActivity;
  String? get profileImageType => _profileImageType;
  String? get profileImagePath => _profileImagePath;
  String get avatarSeed => _avatarSeed;

  // ═══════════════════════════════════════════════════════════════
  // MATCHMAKING STATE
  // ═══════════════════════════════════════════════════════════════
  bool _isMatchmaking = false;
  bool get isMatchmaking => _isMatchmaking;

  void toggleMatchmaking() {
    _isMatchmaking = !_isMatchmaking;
    notifyListeners();
  }

  void startMatchmaking() {
    _isMatchmaking = true;
    notifyListeners();
  }

  void stopMatchmaking() {
    _isMatchmaking = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // WORDS & SENTENCES
  // ═══════════════════════════════════════════════════════════════
  List<Word> _allWords = [];
  List<SentenceViewModel> _allSentences = [];
  List<Map<String, dynamic>> _dailyWords = [];

  List<Word> get allWords => _allWords;
  List<SentenceViewModel> get allSentences => _allSentences;
  List<Map<String, dynamic>> get dailyWords {
    final usableWords = _sanitizeDailyWords(_dailyWords);
    if (usableWords.isNotEmpty) return usableWords;
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    return _buildOfflineDailyWords(todayDate);
  }

  // ═══════════════════════════════════════════════════════════════
  // INITIALIZATION - Uygulama açılışında çağrılır (HIZLI)
  // ═══════════════════════════════════════════════════════════════
  Future<void> initialize() async {
    if (_isInitialized) return; // Tekrar çağrılmasın

    // 🚀 ADIM 1: Önce kelimeleri, sonra cümleleri yükle.
    // Paralel yükleme ilk açılışta cümle cache'inin boş kalmasına neden olabiliyor.
    await _loadWordsFromLocal();
    await _loadSentencesFromLocal();

    // 🎯 ADIM 2: User data'yı hemen yükle (totalWords için kelimeler lazım)
    await _loadUserData();

    _isInitialized = true;
    notifyListeners();

    // 🔄 ADIM 3: Arka planda API sync ve günün kelimeleri (UI'ı bloklamaz)
    _loadDataInBackground();
  }

  /// Arka planda API sync ve günün kelimeleri yükle
  void _loadDataInBackground() {
    Future(() async {
      // Günün kelimeleri (cache varsa hızlı, yoksa AI API'den çeker)
      await _loadDailyWords();

      // Arka planda API ile sync (local veri zaten var)
      await _offlineSyncService.syncPendingChanges();
    });
  }

  /// Sadece LOCAL veritabanından kelimeleri yükle (çok hızlı)
  Future<void> _loadWordsFromLocal() async {
    _isLoadingWords = true;
    try {
      final words = await _offlineSyncService.getLocalWords();
      words.sort((a, b) => b.learnedDate.compareTo(a.learnedDate));
      _allWords = words;
      _isLoadingWords = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading words from local: $e');
      _isLoadingWords = false;
    }
  }

  /// Sadece LOCAL veritabanından cümleleri yükle (çok hızlı)
  Future<void> _loadSentencesFromLocal() async {
    _isLoadingSentences = true;
    try {
      final words = _allWords.isNotEmpty
          ? _allWords
          : await _offlineSyncService.getLocalWords();
      final practiceSentences = await _offlineSyncService.getLocalSentences();

      final List<SentenceViewModel> viewModels = [];
      final Set<int> seenIds = {};

      // Word Sentences
      for (var word in words) {
        for (var s in word.sentences) {
          if (seenIds.contains(s.id)) continue;
          seenIds.add(s.id);
          viewModels.add(SentenceViewModel(
            id: s.id,
            sentence: s.sentence,
            translation: s.translation,
            difficulty: s.difficulty ?? 'easy',
            word: word,
            isPractice: false,
            date: s.createdAt ?? word.learnedDate,
          ));
        }
      }

      // Practice Sentences
      for (var s in practiceSentences) {
        // The /sentences endpoint can return both practice + word-source sentences.
        // Word sentences are already represented via words->sentences, so only keep practice here.
        if (s.source != 'practice') continue;
        viewModels.add(SentenceViewModel(
          id: s.id,
          sentence: s.englishSentence,
          translation: s.turkishTranslation,
          difficulty: s.difficulty,
          word: null,
          isPractice: true,
          date: s.createdDate ?? DateTime.now(),
        ));
      }

      viewModels.sort((a, b) => b.date.compareTo(a.date));
      _allSentences = viewModels;
      _isLoadingSentences = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading sentences from local: $e');
      _isLoadingSentences = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // USER DATA LOADING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadUserData() async {
    try {
      var authUser = await _authService.getUser();
      authUser = await _mergeAiEntitlementSnapshot(authUser);
      final displayName = authUser?['displayName'] ?? 'Kullanıcı';

      // Profile settings
      final prefs = await SharedPreferences.getInstance();
      final type = prefs.getString('profile_image_type') ?? 'avatar';
      final path = prefs.getString('profile_image_path');
      final seed = prefs.getString('profile_avatar_seed') ?? displayName;

      // ═══════════════════════════════════════════════════════════════
      // GERÇEK VERİTABANI DEĞERLERİNİ KULLAN
      // ═══════════════════════════════════════════════════════════════

      // Toplam kelime sayısı = veritabanındaki gerçek kelime sayısı
      final actualTotalWords = _allWords.length;
      final totalSentenceCount = _allWords.fold<int>(
        0,
        (sum, word) => sum + word.sentences.length,
      );

      // XP'yi XPManager'dan al (veritabanından)
      var xpFromManager = await _xpManager.getTotalXP(forceRefresh: true);
      var weeklyXPFromManager =
          await _xpManager.getWeeklyXP(forceRefresh: true);

      // Bazı cihazlarda/veri göçlerinde XP geçmişi boş kalabiliyor.
      // Kelime ve cümlelerden minimum baz XP üretip sadece başlangıç değeri olarak seed et.
      if (xpFromManager <= 0 &&
          (actualTotalWords > 0 || totalSentenceCount > 0)) {
        final estimatedBaseXp =
            (actualTotalWords * 10) + (totalSentenceCount * 5);
        await _seedBaseXpIfMissing(estimatedBaseXp);
        xpFromManager = await _xpManager.getTotalXP(forceRefresh: true);
      }

      // ═══════════════════════════════════════════════════════════════
      // STREAK HESAPLAMASI (SharedPreferences'tan)
      // ═══════════════════════════════════════════════════════════════
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final lastActivityDate = prefs.getString('last_activity_date');
      int currentStreak = prefs.getInt('current_streak') ?? 0;

      // Bugün aktivite var mı kontrol et
      if (lastActivityDate != null && lastActivityDate != todayStr) {
        final lastDate = DateTime.parse(lastActivityDate);
        final today = DateTime.parse(todayStr);
        final diffDays = today.difference(lastDate).inDays;

        if (diffDays > 1) {
          // Seri kırıldı
          currentStreak = 0;
          await prefs.setInt('current_streak', 0);
        }
      }

      // SharedPreferences boş ama kelime geçmişi varsa streak'i kelimelerden geri kur.
      if (currentStreak <= 0 && actualTotalWords > 0) {
        currentStreak = _calculateStreakFromWords(_allWords);
        if (currentStreak > 0) {
          await prefs.setInt('current_streak', currentStreak);
        }
      }

      // Bugünkü öğrenilen kelime sayısı SharedPreferences'tan
      final learnedTodayKey = 'learned_today_$todayStr';

      // DOĞRU HESAPLAMA: Veritabanındaki kelimelerden bugünün kelimelerini say
      final actualLearnedToday = _allWords.where((w) {
        final dateStr = w.learnedDate.toIso8601String().split('T')[0];
        return dateStr == todayStr;
      }).length;

      // SharedPreferences'ı güncelle
      await prefs.setInt(learnedTodayKey, actualLearnedToday);

      final persistedLearnedToday = actualLearnedToday;

      // ═══════════════════════════════════════════════════════════════
      // HAFTALIK AKTİVİTE HESAPLAMASI
      // ═══════════════════════════════════════════════════════════════
      final weeklyActivityFromPrefs =
          await _calculateWeeklyActivityFromPrefs(prefs);
      final hasWeeklyDataFromPrefs =
          weeklyActivityFromPrefs.any((d) => (d['count'] as int? ?? 0) > 0);
      final weeklyActivity = hasWeeklyDataFromPrefs
          ? weeklyActivityFromPrefs
          : _calculateWeeklyActivityFromWords(_allWords);

      // Haftalık XP preflerde yoksa mevcut haftadaki kelime/cümlelerden fallback üret.
      if (weeklyXPFromManager <= 0 &&
          weeklyActivity.any((d) => d['learned'] == true)) {
        weeklyXPFromManager = _estimateWeeklyXpFromWords(_allWords);
      }

      // ═══════════════════════════════════════════════════════════════
      // STATS OLUŞTURMA
      // ═══════════════════════════════════════════════════════════════
      final level = _xpManager.calculateLevel(xpFromManager);

      _userStats = {
        'name': displayName,
        'totalWords': actualTotalWords,
        'streak': currentStreak,
        'xp': xpFromManager,
        'weeklyXP': weeklyXPFromManager,
        'level': level,
        'xpToNextLevel': _xpManager.xpForNextLevel(xpFromManager),
        'dailyGoal': 5,
        'learnedToday': persistedLearnedToday,
        'isOnline': _offlineSyncService.isOnline,
      };

      _userName = displayName;
      _userInfo = authUser;
      _weeklyActivity = weeklyActivity;
      _profileImageType = type;
      _profileImagePath = path;
      _avatarSeed = seed;

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _isLoadingAiEntitlement = false;
      _hasResolvedAiEntitlement = true;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> _mergeAiEntitlementSnapshot(
      Map<String, dynamic>? authUser) async {
    if (authUser == null) {
      _isLoadingAiEntitlement = false;
      _hasResolvedAiEntitlement = false;
      return null;
    }

    final token = await _authService.getToken();
    if (token == null || token.isEmpty) {
      _isLoadingAiEntitlement = false;
      _hasResolvedAiEntitlement = false;
      return authUser;
    }

    _isLoadingAiEntitlement = true;
    notifyListeners();

    try {
      final quota = await _apiService.chatbotQuotaStatus();
      final merged = Map<String, dynamic>.from(authUser)
        ..['aiAccessEnabled'] = quota['aiAccessEnabled'] == true
        ..['planCode'] = quota['planCode']
        ..['trialActive'] = quota['trialActive'] == true
        ..['trialDaysRemaining'] = quota['trialDaysRemaining']
        ..['tokenLimit'] = quota['tokenLimit']
        ..['tokensUsed'] = quota['tokensUsed']
        ..['tokensRemaining'] = quota['tokensRemaining']
        ..['quotaDateUtc'] = quota['dateUtc'];
      await _authService.updateUser(merged);
      _hasResolvedAiEntitlement = true;
      return merged;
    } catch (e) {
      debugPrint('Error loading AI entitlement snapshot: $e');
      _hasResolvedAiEntitlement = true;
      return authUser;
    } finally {
      _isLoadingAiEntitlement = false;
    }
  }

  Future<void> _seedBaseXpIfMissing(int estimatedBaseXp) async {
    if (estimatedBaseXp <= 0) return;
    try {
      final existing = await _xpManager.getTotalXP(forceRefresh: true);
      if (existing > 0) return;

      await _localDb.addXp(estimatedBaseXp);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('total_xp_persistent', estimatedBaseXp);
    } catch (e) {
      debugPrint('Error seeding base XP: $e');
    }
  }

  int _calculateStreakFromWords(List<Word> words) {
    if (words.isEmpty) return 0;
    final dateSet =
        words.map((w) => w.learnedDate.toIso8601String().split('T')[0]).toSet();

    int streak = 0;
    var cursor = DateTime.now();
    final todayStr = cursor.toIso8601String().split('T')[0];

    while (true) {
      final dayStr = cursor.toIso8601String().split('T')[0];
      if (dateSet.contains(dayStr)) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      if (dayStr == todayStr && streak == 0) {
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      break;
    }
    return streak;
  }

  List<Map<String, dynamic>> _calculateWeeklyActivityFromWords(
      List<Word> words) {
    final now = DateTime.now();
    final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    final Map<String, int> dayCounts = {};
    for (final word in words) {
      final key = word.learnedDate.toIso8601String().split('T')[0];
      dayCounts[key] = (dayCounts[key] ?? 0) + 1;
    }

    final weeklyActivity = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final dayDate = weekStart.add(Duration(days: i));
      final dayStr = dayDate.toIso8601String().split('T')[0];
      final count = dayCounts[dayStr] ?? 0;
      weeklyActivity.add({
        'day': days[i],
        'count': count,
        'learned': count > 0,
      });
    }
    return weeklyActivity;
  }

  int _estimateWeeklyXpFromWords(List<Word> words) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDay =
        DateTime(weekStart.year, weekStart.month, weekStart.day);
    final nextWeekStart = weekStartDay.add(const Duration(days: 7));

    int weeklyXp = 0;
    for (final word in words) {
      final learnedDay = DateTime(
          word.learnedDate.year, word.learnedDate.month, word.learnedDate.day);
      if (!learnedDay.isBefore(weekStartDay) &&
          learnedDay.isBefore(nextWeekStart)) {
        weeklyXp += 10; // kelime XP
        weeklyXp += word.sentences.length * 5; // kelimeye bağlı cümle XP
      }
    }
    return weeklyXp;
  }

  /// SharedPreferences'tan haftalık aktiviteyi hesapla
  Future<List<Map<String, dynamic>>> _calculateWeeklyActivityFromPrefs(
      SharedPreferences prefs) async {
    final now = DateTime.now();
    final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

    // Bu haftanın başlangıcını bul (Pazartesi)
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    List<Map<String, dynamic>> weeklyActivity = [];

    for (int i = 0; i < 7; i++) {
      final dayDate = weekStart.add(Duration(days: i));
      final dayStr = dayDate.toIso8601String().split('T')[0];
      final learnedKey = 'learned_today_$dayStr';
      final dayCount = prefs.getInt(learnedKey) ?? 0;

      weeklyActivity.add({
        'day': days[i],
        'count': dayCount,
        'learned': dayCount > 0,
      });
    }

    return weeklyActivity;
  }

  /// Kullanıcı verisini yenile (XP kazanınca vs.)
  Future<void> refreshUserData() async {
    await _loadUserData();
  }

  void _resetSessionScopedState({
    bool notify = true,
    bool clearDailyWords = false,
  }) {
    _isInitialized = false;
    _isLoadingWords = false;
    _isLoadingSentences = false;
    _isLoadingDailyWords = false;
    _isLoadingAiEntitlement = false;
    _hasResolvedAiEntitlement = false;
    _isMatchmaking = false;

    _userName = 'Kullanıcı';
    _userInfo = null;
    _userStats = _buildDefaultUserStats();
    _weeklyActivity = [];

    _profileImageType = null;
    _profileImagePath = null;
    _avatarSeed = '';

    _allWords = [];
    _allSentences = [];
    if (clearDailyWords) {
      _dailyWords = [];
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _hydrateSignedInUserState({
    bool forceDailyWordsRefresh = false,
  }) async {
    await _loadWords();
    await _loadSentences();
    await _loadUserData();
    await _loadDailyWords(
      forceRefresh: forceDailyWordsRefresh || _dailyWords.isEmpty,
    );
  }

  /// Logout veya hesap değişiminde kullanıcıya bağlı in-memory state'i temizle.
  void clearSessionState({bool clearDailyWords = false}) {
    _resetSessionScopedState(
      notify: true,
      clearDailyWords: clearDailyWords,
    );
  }

  /// Profil bilgilerini güncelle
  void updateProfileImage({String? type, String? path, String? seed}) {
    if (type != null) _profileImageType = type;
    if (path != null) _profileImagePath = path;
    if (seed != null) _avatarSeed = seed;
    notifyListeners();
  }

  /// Login sonrası kullanıcı verisini direkt set et (Flicker önlemek için)
  void setUser(Map<String, dynamic> user) {
    _resetSessionScopedState(notify: false);

    _userName = user['displayName'] ?? 'Kullanıcı';
    _userInfo = user;
    _userStats = _buildDefaultUserStats();
    _isLoadingAiEntitlement = true;
    _hasResolvedAiEntitlement = false;

    // Basit istatistikleri varsayılan olarak set et, detaylar sonra yüklenir
    _userStats['name'] = _userName;
    if (user['userTag'] != null) _userStats['userTag'] = user['userTag'];

    _isInitialized = true; // Veri var kabul et
    notifyListeners();

    Future(() async {
      await _hydrateSignedInUserState(forceDailyWordsRefresh: true);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // WORDS LOADING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadWords() async {
    _isLoadingWords = true;
    // İlk açılışta liste boşsa spinner gösterme, direkt yükle

    try {
      final words = await _offlineSyncService.getAllWords();
      // En son eklenen en üstte olacak şekilde sırala
      words.sort((a, b) => b.learnedDate.compareTo(a.learnedDate));

      _allWords = words;
      _isLoadingWords = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading words: $e');
      _isLoadingWords = false;
      notifyListeners();
    }
  }

  /// Kelimeleri yenile (yeni kelime eklendikten sonra)
  Future<void> refreshWords() async {
    await _loadWords();
    await _loadSentencesFromLocal();
    await _loadUserData();
  }

  /// Word Galaxy ve benzeri akislardan SRS review submit et.
  Future<Word?> submitWordReview({
    required int wordId,
    required int quality,
  }) async {
    try {
      final updatedWord = await _apiService.submitWordReview(
        wordId: wordId,
        quality: quality,
      );

      await _localDb.saveWord(updatedWord);

      final index = _allWords.indexWhere((w) => w.id == wordId);
      if (index != -1) {
        _allWords[index] = updatedWord;
      }

      if (_allSentences.isNotEmpty) {
        _allSentences = _allSentences.map((sentenceVm) {
          if (sentenceVm.word?.id != wordId) {
            return sentenceVm;
          }
          return SentenceViewModel(
            id: sentenceVm.id,
            sentence: sentenceVm.sentence,
            translation: sentenceVm.translation,
            difficulty: sentenceVm.difficulty,
            word: updatedWord,
            isPractice: sentenceVm.isPractice,
            date: sentenceVm.date,
          );
        }).toList();
      }

      await _loadUserData();
      notifyListeners();
      return updatedWord;
    } catch (e) {
      debugPrint('Error submitting word review: $e');
      return null;
    }
  }

  /// Kelime ekle - ve listeyi güncelle
  /// XP, toplam kelime ve günlük hedef otomatik güncellenir
  /// source: 'daily_word' | 'quick_dictionary' | 'manual' gibi kaynak bilgisi
  Future<Word?> addWord({
    required String english,
    required String turkish,
    required DateTime addedDate,
    required String difficulty,
    String? source,
  }) async {
    try {
      final newWord = await _offlineSyncService.createWord(
        english: english,
        turkish: turkish,
        addedDate: addedDate,
        difficulty: difficulty,
      );
      if (newWord != null) {
        _allWords.insert(0, newWord); // Başa ekle

        // 🎯 Anlık istatistik güncellemesi (streak, weeklyActivity dahil)
        await incrementLearnedToday(); // totalWords ve learnedToday artırır + streak günceller

        // 🆔 Transaction ID: kelime ID'si (deterministik ve çakışmasız)
        final txId = 'word_id_${newWord.id}';

        // XP ekle - kaynağa göre farklı XP türü (transactionId ile)
        if (source == 'daily_word') {
          await addXPForAction(XPActionTypes.dailyWordLearn,
              source: 'Günün Kelimesi', transactionId: txId);
        } else if (source == 'quick_dictionary') {
          await addXPForAction(XPActionTypes.quickDictionaryAdd,
              source: 'Hızlı Sözlük', transactionId: txId);
        } else {
          await addXPForAction(XPActionTypes.addWord,
              source: source, transactionId: txId);
        }

        notifyListeners();
      }
      return newWord;
    } catch (e) {
      debugPrint('Error adding word: $e');
      return null;
    }
  }

  /// Kelime sil
  Future<bool> deleteWord(int wordId) async {
    try {
      // Silinecek kelimenin cümle sayısını local DB'den al (stale ID fallback dahil)
      int sentenceCount =
          await _offlineSyncService.getSentenceCountForWord(wordId);
      Word? wordToDelete;
      try {
        wordToDelete = _allWords.firstWhere((w) => w.id == wordId);
      } catch (_) {
        wordToDelete = null;
      }
      if (sentenceCount == 0 && wordToDelete != null) {
        final unique = <String>{};
        for (final s in wordToDelete.sentences) {
          final key =
              s.sentence.trim().replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();
          if (key.isEmpty) continue;
          unique.add(key);
        }
        sentenceCount = unique.length;
      }

      final deleted = await _offlineSyncService.deleteWord(wordId);
      if (!deleted) {
        return false;
      }

      // Kelimeyi listeden kaldır
      _allWords.removeWhere((w) => w.id == wordId);

      // İstatistikleri güncelle (Kelime sayısı ve bugün öğrenilenler)
      _userStats['totalWords'] = _allWords.length;

      // Eğer bugünün kelimesi silindiyse, learnedToday'i güncelle
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final learnedTodayCount = _allWords.where((w) {
        final dStr = w.learnedDate.toIso8601String().split('T')[0];
        return dStr == todayStr;
      }).length;

      _userStats['learnedToday'] = learnedTodayCount;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('learned_today_$todayStr', learnedTodayCount);

      // 🔥 XP düşür: kelime (10 XP) + her cümle (5 XP)
      // XPManager.deductXP hem local DB hem SharedPreferences'i günceller
      final xpToDeduct = 10 + (sentenceCount * 5);
      final deletedWordName = wordToDelete?.englishWord ?? 'Bilinmeyen Kelime';
      await _xpManager.deductXP(xpToDeduct, 'Kelime silindi: $deletedWordName');

      // UI state'i de güncelle (XPManager callback'i bu işi yapacak ama yine de yapalım)
      final newTotalXp = await _xpManager.getTotalXP(forceRefresh: true);
      _userStats['xp'] = newTotalXp;
      _userStats['level'] = _xpManager.calculateLevel(newTotalXp);
      _userStats['xpToNextLevel'] = _xpManager.xpForNextLevel(newTotalXp);

      // Map referansını değiştir (UI güncellemesi için)
      _userStats = Map<String, dynamic>.from(_userStats);

      // 🔥 Silinen kelimenin cümlelerini de listeden kaldır
      _allSentences.removeWhere((s) => s.word?.id == wordId);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting word: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SENTENCES LOADING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadSentences() async {
    _isLoadingSentences = true;
    notifyListeners();

    try {
      // 🚀 Optimizasyon: Kelimeler zaten yüklüyse onları kullan
      List<Word> words = _allWords;
      if (words.isEmpty) {
        // Kelimeler henüz yüklenmemişse yükle
        words = await _offlineSyncService.getAllWords();
      }

      // Practice sentences'ı paralel olarak yükle
      // Force server reconciliation so stale/ghost practice rows don't linger.
      final practiceSentences =
          await _offlineSyncService.getAllSentences(forceRefresh: true);

      final List<SentenceViewModel> viewModels = [];
      final Set<int> seenIds = {};

      // Word Sentences - mevcut kelimelerden
      for (var word in words) {
        for (var s in word.sentences) {
          if (seenIds.contains(s.id)) continue;
          seenIds.add(s.id);

          viewModels.add(SentenceViewModel(
            id: s.id,
            sentence: s.sentence,
            translation: s.translation,
            difficulty: s.difficulty ?? 'easy',
            word: word,
            isPractice: false,
            date: word.learnedDate,
          ));
        }
      }

      // Practice Sentences
      for (var s in practiceSentences) {
        // The /sentences endpoint can return both practice + word-source sentences.
        // Word sentences are already represented via words->sentences, so only keep practice here.
        if (s.source != 'practice') continue;

        viewModels.add(SentenceViewModel(
          id: s.id,
          sentence: s.englishSentence,
          translation: s.turkishTranslation,
          difficulty: s.difficulty,
          word: null,
          isPractice: true,
          date: s.createdDate ?? DateTime.now(),
        ));
      }

      // Sort: Newest first
      viewModels.sort((a, b) => b.date.compareTo(a.date));

      _allSentences = viewModels;
      _isLoadingSentences = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading sentences: $e');
      _isLoadingSentences = false;
      notifyListeners();
    }
  }

  /// Cümleleri yenile
  Future<void> refreshSentences() async {
    await _loadSentences();
  }

  /// Kelimeye cümle ekle ve listeyi güncelle
  /// XP otomatik eklenir, cümle listesi anında güncellenir
  Future<Word?> addSentenceToWord({
    required int wordId,
    required String sentence,
    required String translation,
    String difficulty = 'easy',
  }) async {
    // 🆔 Transaction ID oluştur ÖNCE - içerik tabanlı (cümle hash + kelime ID)
    final txId = 'sentence_${wordId}_${sentence.toLowerCase().hashCode}';

    try {
      final updatedWord = await _offlineSyncService.addSentenceToWord(
        wordId: wordId,
        sentence: sentence,
        translation: translation,
        difficulty: difficulty,
      );

      if (updatedWord != null) {
        // Kelime listesini güncelle
        final index = _allWords.indexWhere((w) => w.id == wordId);
        if (index != -1) {
          _allWords[index] = updatedWord;
        }

        // XP ekle (cümle başına 5 XP) - içerik tabanlı txId ile
        await addXPForAction(XPActionTypes.addSentence,
            source: 'Cümle Ekleme', transactionId: txId);

        // Cümle listesini ANLINDA güncelle (UI hemen görsün)
        // 🔥 Önce aynı cümle var mı kontrol et (çift eklemeyi engelle)
        if (updatedWord.sentences.isNotEmpty) {
          String norm(String value) {
            final trimmed = value.trim();
            if (trimmed.isEmpty) return '';
            return trimmed.replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();
          }

          // Local DB sentences ordering is not guaranteed (and may be createdAt DESC),
          // so find the most likely "just added" sentence by content.
          final targetSentence = norm(sentence);
          final targetTranslation = norm(translation);
          Sentence? newSentence;
          for (final s in updatedWord.sentences) {
            if (norm(s.sentence) == targetSentence &&
                norm(s.translation) == targetTranslation) {
              newSentence = s;
              break;
            }
          }
          newSentence ??= updatedWord.sentences.first;

          // Aynı cümle zaten listede var mı?
          final alreadyExists = _allSentences.any((s) =>
              s.sentence == newSentence!.sentence &&
              s.translation == newSentence.translation &&
              s.word?.id == wordId);

          if (!alreadyExists) {
            _allSentences.insert(
                0,
                SentenceViewModel(
                  id: newSentence.id,
                  sentence: newSentence.sentence,
                  translation: newSentence.translation,
                  difficulty: newSentence.difficulty ?? 'easy',
                  word: updatedWord,
                  isPractice: false,
                  date: newSentence.createdAt ?? DateTime.now(),
                ));
          }
        }

        notifyListeners();
      } else {
        // Fallback: ID eşleşme sorunlarında local DB'den yeniden yükle.
        await refreshWords();
        await refreshSentences();
      }
      return updatedWord;
    } catch (e) {
      debugPrint('Error adding sentence: $e');
      return null;
    }
  }

  /// Bağımsız pratik cümlesi ekle (kelimeye bağlı olmayan)
  /// XP otomatik eklenir, cümle listesi anında güncellenir
  Future<bool> addPracticeSentence({
    required String englishSentence,
    required String turkishTranslation,
    String difficulty = 'medium',
  }) async {
    // 🆔 Transaction ID oluştur ÖNCE - içerik tabanlı
    final txId = 'practice_${englishSentence.toLowerCase().hashCode}';

    try {
      final newSentence = await _offlineSyncService.createSentence(
        englishSentence: englishSentence,
        turkishTranslation: turkishTranslation,
        difficulty: difficulty,
      );

      if (newSentence != null) {
        // 🔥 Önce aynı cümle var mı kontrol et (çift eklemeyi engelle)
        final alreadyExists = _allSentences.any((s) =>
            s.sentence == englishSentence &&
            s.translation == turkishTranslation &&
            s.isPractice == true);

        if (!alreadyExists) {
          // Cümle listesini ANLINDA güncelle (UI hemen görsün)
          _allSentences.insert(
              0,
              SentenceViewModel(
                id: newSentence.id,
                sentence: newSentence.englishSentence,
                translation: newSentence.turkishTranslation,
                difficulty: difficulty,
                word: null,
                isPractice: true,
                date: DateTime.now(),
              ));
        }

        // XP ekle (pratik cümlesi başına 5 XP) - içerik tabanlı txId ile
        await addXPForAction(XPActionTypes.addPracticeSentence,
            source: 'Pratik Cümlesi', transactionId: txId);

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error adding practice sentence: $e');
      return false;
    }
  }

  /// Kelimeye bağlı cümleyi sil (UI anında güncellenir)
  Future<bool> deleteSentenceFromWord(
      {required int wordId, required int sentenceId}) async {
    try {
      String norm(String value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return '';
        return trimmed.replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();
      }

      // Duplicate sentence rows (same sentence text) can happen in offline->online flows.
      // If the user is deleting only the duplicate copy, do NOT deduct XP again.
      bool shouldDeductXp = true;
      String? targetSentenceKey;
      String? targetTranslationKey;
      int effectiveWordId = wordId;
      String? targetWordEnglish;
      for (final w in _allWords) {
        try {
          final matched = w.sentences.firstWhere((s) => s.id == sentenceId);
          targetSentenceKey = norm(matched.sentence);
          targetTranslationKey = norm(matched.translation);
          effectiveWordId = w.id;
          targetWordEnglish = w.englishWord;
          final hasAnother = w.sentences.any((s) =>
              s.id != sentenceId && norm(s.sentence) == targetSentenceKey);
          if (hasAnother) shouldDeductXp = false;
          break;
        } catch (_) {}
      }

      // Fallback: if the word list is stale, use the sentence view-model list.
      if (targetSentenceKey == null) {
        for (final s in _allSentences) {
          if (!s.isPractice && s.id == sentenceId) {
            targetSentenceKey = norm(s.sentence);
            targetTranslationKey = norm(s.translation);
            effectiveWordId = s.word?.id ?? wordId;
            targetWordEnglish = s.word?.englishWord;
            break;
          }
        }
        final sentenceKey = targetSentenceKey;
        if (sentenceKey != null && sentenceKey.isNotEmpty) {
          final hasAnother = _allSentences.any((s) {
            if (s.isPractice) return false;
            if (s.id == sentenceId) return false;
            final sid = s.word?.id;
            if (sid == null) return false;
            return sid == effectiveWordId && norm(s.sentence) == sentenceKey;
          });
          if (hasAnother) {
            shouldDeductXp = false;
          }
        }
      }

      final deleted = await _offlineSyncService.deleteSentenceFromWord(
        wordId: wordId,
        sentenceId: sentenceId,
      );
      if (!deleted) {
        return false;
      }

      // 🔥 UI'dan anında kaldır
      final effectiveWord = _allWords.firstWhere(
        (w) => w.id == effectiveWordId || w.id == wordId,
        orElse: () => Word(
            id: wordId,
            englishWord: '',
            turkishMeaning: '',
            learnedDate: DateTime.now(),
            difficulty: 'easy',
            sentences: const []),
      );
      targetWordEnglish ??= (effectiveWord.englishWord.isNotEmpty
          ? effectiveWord.englishWord
          : null);

      bool matchesTargetWord(SentenceViewModel vm) {
        final vmWord = vm.word;
        if (vmWord == null) return false;
        if (vmWord.id == effectiveWordId || vmWord.id == wordId) return true;
        final wordEnglish = targetWordEnglish;
        if (wordEnglish == null || wordEnglish.trim().isEmpty) {
          return false;
        }
        return norm(vmWord.englishWord) == norm(wordEnglish);
      }

      // Remove by ID and also by content, to handle localId->serverId remaps leaving stale VMs behind.
      _allSentences.removeWhere((vm) {
        if (vm.isPractice) return false;
        if (vm.id.toString() == sentenceId.toString()) return true;
        final sentenceKey = targetSentenceKey;
        if (sentenceKey == null || sentenceKey.isEmpty) return false;
        if (norm(vm.sentence) != sentenceKey) return false;
        if (!matchesTargetWord(vm)) return false;
        // Translation can differ (some users leave it blank), so only use it if we have it.
        final translationKey = targetTranslationKey;
        if (translationKey != null &&
            translationKey.isNotEmpty &&
            norm(vm.translation) != translationKey) {
          return false;
        }
        return true;
      });

      // Kelime içindeki cümleyi de güncelle
      final indices = <int>{};
      for (int i = 0; i < _allWords.length; i++) {
        final id = _allWords[i].id;
        final wordEnglish = targetWordEnglish;
        if (id == wordId || id == effectiveWordId) {
          indices.add(i);
        } else if (wordEnglish != null &&
            wordEnglish.trim().isNotEmpty &&
            norm(_allWords[i].englishWord) == norm(wordEnglish)) {
          indices.add(i);
        }
      }

      for (final idx in indices) {
        final word = _allWords[idx];
        final updatedSentences = word.sentences.where((s) {
          if (s.id == sentenceId) return false;
          final sentenceKey = targetSentenceKey;
          if (sentenceKey != null &&
              sentenceKey.isNotEmpty &&
              norm(s.sentence) == sentenceKey) {
            final translationKey = targetTranslationKey;
            if (translationKey != null &&
                translationKey.isNotEmpty &&
                norm(s.translation) != translationKey) {
              return true;
            }
            return false;
          }
          return true;
        }).toList();

        _allWords[idx] = Word(
          id: word.id,
          englishWord: word.englishWord,
          turkishMeaning: word.turkishMeaning,
          learnedDate: word.learnedDate,
          difficulty: word.difficulty,
          notes: word.notes,
          sentences: updatedSentences,
        );
      }

      // 🔥 XP düşür: cümle başına 5 XP
      // XPManager.deductXP hem local DB hem SharedPreferences'i günceller
      if (shouldDeductXp) {
        final sentenceKey = targetSentenceKey;
        final contentKey = (sentenceKey != null && sentenceKey.isNotEmpty)
            ? '$sentenceKey|${targetTranslationKey ?? ''}'
            : 'id:$sentenceId';
        final txId =
            'deduct_sentence_${effectiveWordId}_${contentKey.hashCode}';
        await _xpManager.deductXP(5, 'Cümle silindi', transactionId: txId);
      }

      // UI state'i de güncelle
      final newTotalXp = await _xpManager.getTotalXP(forceRefresh: true);
      _userStats['xp'] = newTotalXp;
      _userStats['level'] = _xpManager.calculateLevel(newTotalXp);
      _userStats['xpToNextLevel'] = _xpManager.xpForNextLevel(newTotalXp);

      // Map referansını değiştir (UI güncellemesi için)
      _userStats = Map<String, dynamic>.from(_userStats);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting sentence: $e');
      return false;
    }
  }

  /// Pratik cümlesini sil (UI anında güncellenir)
  Future<bool> deletePracticeSentence(dynamic sentenceId) async {
    try {
      String norm(String value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return '';
        return trimmed.replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();
      }

      SentenceViewModel? targetVm;
      for (final s in _allSentences) {
        if (!s.isPractice) continue;
        if (s.id.toString() == sentenceId.toString()) {
          targetVm = s;
          break;
        }
      }
      final targetSentence = targetVm != null ? norm(targetVm.sentence) : '';
      final targetTranslation =
          targetVm != null ? norm(targetVm.translation) : '';

      final deleted = await _offlineSyncService
          .deletePracticeSentence(sentenceId.toString());
      if (!deleted) {
        return false;
      }

      // 🔥 UI'dan anında kaldır
      _allSentences.removeWhere((s) {
        if (!s.isPractice) return false;
        if (s.id.toString() == sentenceId.toString()) return true;
        if (targetSentence.isEmpty) return false;
        if (norm(s.sentence) != targetSentence) return false;
        if (targetTranslation.isNotEmpty &&
            norm(s.translation) != targetTranslation) {
          return false;
        }
        return true;
      });

      // 🔥 XP düşür: pratik cümlesi başına 5 XP
      // XPManager.deductXP hem local DB hem SharedPreferences'i günceller
      final contentKey = targetSentence.isNotEmpty
          ? '$targetSentence|$targetTranslation'
          : 'id:${sentenceId.toString()}';
      final txId = 'deduct_practice_${contentKey.hashCode}';
      await _xpManager.deductXP(5, 'Pratik cümlesi silindi',
          transactionId: txId);

      // UI state'i de güncelle
      final newTotalXp = await _xpManager.getTotalXP(forceRefresh: true);
      _userStats['xp'] = newTotalXp;
      _userStats['level'] = _xpManager.calculateLevel(newTotalXp);
      _userStats['xpToNextLevel'] = _xpManager.xpForNextLevel(newTotalXp);

      // Map referansını değiştir (UI güncellemesi için)
      _userStats = Map<String, dynamic>.from(_userStats);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting practice sentence: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DAILY WORDS (Günün Kelimeleri - AI Generated)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadDailyWords({bool forceRefresh = false}) async {
    _isLoadingDailyWords = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDate = prefs.getString('daily_words_date');
      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final cachedJson = prefs.getString('daily_words_cache');

      if (!forceRefresh && lastDate == todayDate && cachedJson != null) {
        // Cache'den yükle; boş cache eski oturum/reinstall senaryosunda ekranı kilitlemesin.
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final cachedWords = _sanitizeDailyWords(decoded);
        if (cachedWords.isNotEmpty) {
          _dailyWords = cachedWords;
          _isLoadingDailyWords = false;
          notifyListeners();
          return;
        }
      }

      // Yeni veri getir
      List<Map<String, dynamic>> words = await _apiService.getDailyWords();
      if (words.isEmpty) {
        // Backward-compatible fallback (BYOK) for dev/offline environments.
        words = await GroqService.getDailyWords();
      }
      words = _sanitizeDailyWords(words);
      if (words.isEmpty) {
        words = _buildOfflineDailyWords(todayDate);
      }

      _dailyWords = words;
      // Cache'e kaydet
      await prefs.setString('daily_words_date', todayDate);
      await prefs.setString('daily_words_cache', jsonEncode(words));

      _isLoadingDailyWords = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading daily words: $e');
      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      _dailyWords = _buildOfflineDailyWords(todayDate);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('daily_words_date', todayDate);
        await prefs.setString('daily_words_cache', jsonEncode(_dailyWords));
      } catch (_) {}
      _isLoadingDailyWords = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _sanitizeDailyWords(Iterable<dynamic> rawWords) {
    return rawWords
        .whereType<Map>()
        .map((word) => Map<String, dynamic>.from(word))
        .where((word) {
      final english =
          (word['word'] ?? word['englishWord'] ?? '').toString().trim();
      return english.isNotEmpty;
    }).toList();
  }

  List<Map<String, dynamic>> _buildOfflineDailyWords(String dateKey) {
    final seed = dateKey.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final pool = <Map<String, dynamic>>[
      {
        'word': 'resilient',
        'translation': 'dayanikli',
        'definition': 'Able to recover quickly after difficulty.',
        'exampleSentence': 'A resilient plan can survive unexpected changes.',
        'exampleTranslation':
            'Dayanikli bir plan beklenmeyen degisikliklere dayanabilir.',
        'partOfSpeech': 'adjective',
        'difficulty': 'medium',
        'synonyms': ['flexible', 'strong'],
      },
      {
        'word': 'clarify',
        'translation': 'acikliga kavusturmak',
        'definition': 'To make an idea or statement easier to understand.',
        'exampleSentence': 'Can you clarify the main goal of the project?',
        'exampleTranslation':
            'Projenin ana hedefini acikliga kavusturabilir misin?',
        'partOfSpeech': 'verb',
        'difficulty': 'easy',
        'synonyms': ['explain', 'simplify'],
      },
      {
        'word': 'insight',
        'translation': 'kavrayis',
        'definition': 'A clear understanding of a person, situation, or idea.',
        'exampleSentence': 'The chart gave us useful insight into user habits.',
        'exampleTranslation':
            'Grafik bize kullanici aliskanliklari hakkinda faydali kavrayis sagladi.',
        'partOfSpeech': 'noun',
        'difficulty': 'medium',
        'synonyms': ['understanding', 'awareness'],
      },
      {
        'word': 'adapt',
        'translation': 'uyum saglamak',
        'definition': 'To change so something works better in a new situation.',
        'exampleSentence': 'Teams adapt faster when feedback is clear.',
        'exampleTranslation':
            'Geri bildirim net oldugunda ekipler daha hizli uyum saglar.',
        'partOfSpeech': 'verb',
        'difficulty': 'easy',
        'synonyms': ['adjust', 'modify'],
      },
      {
        'word': 'evaluate',
        'translation': 'degerlendirmek',
        'definition':
            'To judge the value, quality, or importance of something.',
        'exampleSentence': 'We evaluate each answer before saving it.',
        'exampleTranslation': 'Her cevabi kaydetmeden once degerlendiririz.',
        'partOfSpeech': 'verb',
        'difficulty': 'medium',
        'synonyms': ['assess', 'review'],
      },
      {
        'word': 'consistent',
        'translation': 'tutarli',
        'definition': 'Acting or happening in the same reliable way over time.',
        'exampleSentence':
            'Consistent practice makes new words easier to remember.',
        'exampleTranslation':
            'Tutarli pratik yeni kelimeleri hatirlamayi kolaylastirir.',
        'partOfSpeech': 'adjective',
        'difficulty': 'easy',
        'synonyms': ['steady', 'regular'],
      },
      {
        'word': 'prioritize',
        'translation': 'oncelik vermek',
        'definition': 'To decide which tasks or ideas are most important.',
        'exampleSentence': 'Prioritize the words you forget most often.',
        'exampleTranslation': 'En sik unuttugun kelimelere oncelik ver.',
        'partOfSpeech': 'verb',
        'difficulty': 'medium',
        'synonyms': ['rank', 'focus'],
      },
    ];

    return List.generate(5, (index) {
      final word = pool[(seed + index) % pool.length];
      return Map<String, dynamic>.from(word);
    });
  }

  /// Günün kelimelerini yenile
  Future<void> refreshDailyWords() async {
    await _loadDailyWords(forceRefresh: true);
  }

  // ═══════════════════════════════════════════════════════════════
  // XP & STATS UPDATES
  // ═══════════════════════════════════════════════════════════════

  /// Kullanıcı istatistiklerini manuel güncelle
  void updateUserStats(Map<String, dynamic> newStats) {
    if (newStats.isEmpty) return;

    newStats.forEach((key, value) {
      if (value != null) {
        _userStats[key] = value;
      }
    });

    notifyListeners();
  }

  /// Haftalık aktivite verisini güncelle
  void updateWeeklyActivity(List<Map<String, dynamic>> activity) {
    _weeklyActivity = activity;
    notifyListeners();
  }

  /// XP ekle ve state'i güncelle (eskiyi korumak için backward compatible)
  /// Öncelik: Spesifik action type methodlarını kullanın
  Future<int> addXP(int amount, {String? reason}) async {
    try {
      final added = await _xpManager.addCustomXP(amount, reason ?? 'custom');

      // WeeklyXP'yi de güncelle
      final currentWeeklyXP = (_userStats['weeklyXP'] as int?) ?? 0;
      final nextWeeklyXP = currentWeeklyXP + added;
      _userStats['weeklyXP'] = nextWeeklyXP < 0 ? 0 : nextWeeklyXP;

      // Level kontrolü
      final totalXP = _userStats['xp'] ?? 0;
      _userStats['level'] = _xpManager.calculateLevel(totalXP);
      _userStats['xpToNextLevel'] = _xpManager.xpForNextLevel(totalXP);

      notifyListeners();
      return added;
    } catch (e) {
      debugPrint('Error adding XP: $e');
      return 0;
    }
  }

  /// XP Manager'ı direkt kullanarak spesifik aksiyon için XP ekle
  /// [transactionId]: Opsiyonel benzersiz işlem ID'si - idempotency için
  Future<int> addXPForAction(XPActionType action,
      {String? source, String? transactionId}) async {
    try {
      final added = await _xpManager.addXP(action,
          source: source, transactionId: transactionId);
      return added;
    } catch (e) {
      debugPrint('Error adding XP for action: $e');
      return 0;
    }
  }

  /// Bugün öğrenilen kelime sayısını artır ve kalıcı olarak kaydet
  Future<void> incrementLearnedToday() async {
    _userStats['learnedToday'] = (_userStats['learnedToday'] ?? 0) + 1;
    // totalWords = veritabanındaki gerçek kelime sayısı
    _userStats['totalWords'] = _allWords.length;

    // SharedPreferences'a kaydet
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _now.toIso8601String().split('T')[0];
    final learnedTodayKey = 'learned_today_$todayStr';
    await prefs.setInt(learnedTodayKey, _userStats['learnedToday']);

    // Streak güncelle
    await _updateStreak();

    // Haftalık aktiviteyi güncelle
    _updateWeeklyActivityForToday();

    notifyListeners();

    // Günlük hedef kontrolü
    await _checkDailyGoal();
  }

  /// Test için tarih mocklama
  @visibleForTesting
  DateTime? mockDate;

  DateTime get _now => mockDate ?? DateTime.now();

  /// Streak'i güncelle ve kaydet
  Future<void> _updateStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _now.toIso8601String().split('T')[0];
    final lastActivityDate = prefs.getString('last_activity_date');

    int currentStreak = prefs.getInt('current_streak') ?? 0;

    if (lastActivityDate == null) {
      // İlk aktivite
      currentStreak = 1;
    } else if (lastActivityDate != todayStr) {
      final lastDate = DateTime.parse(lastActivityDate);
      final today = DateTime.parse(todayStr);
      final diffDays = today.difference(lastDate).inDays;

      if (diffDays == 1) {
        // Ardışık gün, streak artır
        currentStreak += 1;
      } else if (diffDays > 1) {
        // Seri kırıldı, yeniden başla
        currentStreak = 1;
      }
      // diffDays == 0 ise aynı gün, streak değişmez
    }

    // Kaydet
    await prefs.setString('last_activity_date', todayStr);
    await prefs.setInt('current_streak', currentStreak);

    _userStats['streak'] = currentStreak;

    // Streak bonuslarını kontrol et
    await _xpManager.checkAndAwardStreakBonus(currentStreak);
  }

  /// Günlük hedef kontrolü
  Future<void> _checkDailyGoal() async {
    final learnedToday = _userStats['learnedToday'] ?? 0;
    final dailyGoal = _userStats['dailyGoal'] ?? 5;

    if (learnedToday >= dailyGoal) {
      await _xpManager.checkDailyGoal(learnedToday, dailyGoal);
    }
  }

  /// Streak bonuslarını kontrol et
  Future<void> checkStreakBonus() async {
    final streak = _userStats['streak'] ?? 0;
    await _xpManager.checkAndAwardStreakBonus(streak);
  }

  /// Bugünkü haftalık aktiviteyi güncelle
  void _updateWeeklyActivityForToday() {
    final today = _now;
    final dayIndex = today.weekday - 1; // 0 = Pazartesi, 6 = Pazar

    if (_weeklyActivity.isEmpty) {
      // Haftalık aktivite listesi oluştur
      final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
      _weeklyActivity = List.generate(
          7,
          (i) => <String, dynamic>{
                'day': days[i],
                'count': 0,
                'learned': false,
              });
    }

    if (dayIndex >= 0 && dayIndex < _weeklyActivity.length) {
      final currentCount = _weeklyActivity[dayIndex]['count'] ?? 0;
      _weeklyActivity[dayIndex] = {
        ..._weeklyActivity[dayIndex],
        'count': currentCount + 1,
        'learned': true,
      };
    }
  }

  /// XP Manager getter (diğer servisler için)
  XPManager get xpManager => _xpManager;

  // ═══════════════════════════════════════════════════════════════
  // DAILY WORD HELPERS
  // ═══════════════════════════════════════════════════════════════

  Word? findWordByEnglish(String english) {
    final target = english.trim().toLowerCase();
    if (target.isEmpty) return null;
    try {
      return _allWords.firstWhere(
        (w) => (w.englishWord).trim().toLowerCase() == target,
      );
    } catch (_) {
      return null;
    }
  }

  bool hasSentenceForWord(Word word, String sentence) {
    final target = sentence.trim().toLowerCase();
    if (target.isEmpty) return false;
    return word.sentences.any((s) => s.sentence.trim().toLowerCase() == target);
  }
}
