import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/offline_sync_service.dart';
import '../services/local_database_service.dart';
import '../models/word.dart';

/// Hesaba özel verileri yöneten servis
/// eren@gmail.com (#81726) hesabı için DB verilerini gösterir
/// Diğer hesaplar için boş/sıfır veriler döner
/// OFFLINE DESTEKLI - internet olmasa da veriler yerel DB'den gelir
class UserDataService {
  static final UserDataService _instance = UserDataService._internal();
  factory UserDataService() => _instance;
  UserDataService._internal();

  final AuthService _authService = AuthService();
  final OfflineSyncService _offlineSyncService = OfflineSyncService();
  final LocalDatabaseService _localDb = LocalDatabaseService();

  // Ana hesap bilgileri
  static const String mainAccountEmail = 'eren@gmail.com';
  static const String mainAccountUserTag = '#81726';

  /// Bu hesap ana hesap mı kontrol et
  Future<bool> isMainAccount() async {
    final user = await _authService.getUser();
    if (user == null) {
      debugPrint('🔴 UserDataService: User is null!');
      return false;
    }
    
    final email = user['email'] as String?;
    final userTag = user['userTag'] as String?;
    
    debugPrint('🔍 UserDataService: Checking account - email: $email, userTag: $userTag');
    debugPrint('🔍 UserDataService: Main account email: $mainAccountEmail, tag: $mainAccountUserTag');
    
    final isMain = email == mainAccountEmail || userTag == mainAccountUserTag;
    debugPrint('🔍 UserDataService: isMainAccount = $isMain');
    
    return isMain;
  }

  /// Kelime listesini getir (sadece ana hesap için)
  /// OFFLINE DESTEKLI
  Future<List<Word>> getWords() async {
    final isMain = await isMainAccount();
    debugPrint('📚 UserDataService.getWords: isMainAccount = $isMain');
    
    if (isMain) {
      final words = await _offlineSyncService.getAllWords();
      debugPrint('📚 UserDataService.getWords: Found ${words.length} words');
      return words;
    }
    debugPrint('📚 UserDataService.getWords: Not main account, returning empty list');
    return []; // Diğer hesaplar için boş liste
  }

  /// Tarihleri getir (sadece ana hesap için)
  /// OFFLINE DESTEKLI
  Future<List<String>> getWordDates() async {
    if (await isMainAccount()) {
      return await _offlineSyncService.getAllDistinctDates();
    }
    return []; // Diğer hesaplar için boş liste
  }

  /// Toplam kelime sayısı
  Future<int> getTotalWords() async {
    final words = await getWords();
    return words.length;
  }

  /// XP hesapla (yerel DB'den + kelime sayısına göre)
  /// OFFLINE DESTEKLI
  Future<int> getTotalXP() async {
    if (!await isMainAccount()) return 0;
    
    // Önce local DB'deki XP'yi kontrol et
    final localXp = await _localDb.getTotalXp();
    
    // Eğer local XP varsa onu kullan
    if (localXp > 0) {
      return localXp;
    }
    
    // Yoksa kelime sayısına göre hesapla
    final totalWords = await getTotalWords();
    return totalWords * 10;
  }

  /// Seviye hesapla
  Future<int> getLevel() async {
    final xp = await getTotalXP();
    return (xp / 100).floor() + 1;
  }

  /// Bugün öğrenilen kelimeler
  Future<int> getLearnedToday() async {
    final words = await getWords();
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    return words.where((w) => 
      w.learnedDate.toIso8601String().split('T')[0] == todayStr
    ).length;
  }

  /// Streak hesapla
  Future<int> getStreak() async {
    if (!await isMainAccount()) return 0;

    final dates = (await getWordDates()).toSet();
    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];
    
    int streak = 0;
    DateTime date = now;
    
    while (true) {
      final dStr = date.toIso8601String().split('T')[0];
      if (dates.contains(dStr)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else {
        if (dStr == todayStr && streak == 0) {
          date = date.subtract(const Duration(days: 1));
          continue;
        }
        break;
      }
    }
    return streak;
  }

  /// Haftalık aktivite
  Future<List<Map<String, dynamic>>> getWeeklyActivity() async {
    final words = await getWords();
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    
    final List<Map<String, dynamic>> calendar = [];
    
    for (int i = 0; i < 7; i++) {
      final dayDate = monday.add(Duration(days: i));
      final dayStr = dayDate.toIso8601String().split('T')[0];
      final count = words.where((w) => 
        w.learnedDate.toIso8601String().split('T')[0] == dayStr
      ).length;
      
      final dayName = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i];
      
      calendar.add({
        'day': dayName,
        'learned': count > 0,
        'count': count,
      });
    }
    
    return calendar;
  }

  /// Haftalık XP
  Future<int> getWeeklyXP() async {
    final calendar = await getWeeklyActivity();
    int total = 0;
    for (var day in calendar) {
      total += (day['count'] as int) * 10;
    }
    return total;
  }

  /// Tüm istatistikleri getir
  /// OFFLINE DESTEKLI
  Future<Map<String, dynamic>> getAllStats() async {
    final user = await _authService.getUser();
    final displayName = user?['displayName'] ?? 'Kullanıcı';
    
    final isMain = await isMainAccount();
    
    if (!isMain) {
      // Diğer hesaplar için sıfır veriler
      return {
        'name': displayName,
        'level': 1,
        'xp': 0,
        'xpToNextLevel': 100,
        'totalWords': 0,
        'streak': 0,
        'weeklyXP': 0,
        'dailyGoal': 5,
        'learnedToday': 0,
        'isOnline': _offlineSyncService.isOnline,
      };
    }

    final totalWords = await getTotalWords();
    final xp = await getTotalXP();
    final level = await getLevel();
    final streak = await getStreak();
    final weeklyXP = await getWeeklyXP();
    final learnedToday = await getLearnedToday();
    final pendingXp = await _localDb.getPendingXp();
    
    return {
      'name': displayName,
      'level': level,
      'xp': xp,
      'xpToNextLevel': level * 100,
      'totalWords': totalWords,
      'streak': streak,
      'weeklyXP': weeklyXP,
      'dailyGoal': 5,
      'learnedToday': learnedToday,
      'isOnline': _offlineSyncService.isOnline,
      'pendingXp': pendingXp, // Senkronize edilmemiş XP
    };
  }

  /// Arkadaş listesi (şimdilik boş - gerçek bir arkadaş sistemi eklenene kadar)
  Future<List<Map<String, dynamic>>> getFriends() async {
    // Gerçek bir arkadaş sistemi olmadığı için boş liste
    return [];
  }

  /// Çevrimiçi kullanıcılar (şimdilik boş)
  Future<List<Map<String, dynamic>>> getOnlineUsers() async {
    // Gerçek bir online sistem olmadığı için boş liste
    return [];
  }

  /// Başarılar (gerçek verilere göre hesapla)
  Future<List<Map<String, dynamic>>> getAchievements() async {
    final totalWords = await getTotalWords();
    final streak = await getStreak();
    final level = await getLevel();
    
    return [
      {
        'title': 'İlk Adım',
        'desc': 'İlk kelimeni öğrendin',
        'icon': '🎯',
        'unlocked': totalWords >= 1,
      },
      {
        'title': '7 Gün Serisi',
        'desc': '7 gün üst üste çalıştın',
        'icon': '🔥',
        'unlocked': streak >= 7,
      },
      {
        'title': '100 Kelime',
        'desc': '100 kelime öğrendin',
        'icon': '💯',
        'unlocked': totalWords >= 100,
      },
      {
        'title': 'Haftalık Kahraman',
        'desc': 'Haftada 50 kelime öğren',
        'icon': '⭐',
        'unlocked': await getWeeklyXP() >= 500, // 50 kelime = 500 XP
      },
      {
        'title': 'Seviye 10',
        'desc': '10. seviyeye ulaş',
        'icon': '🏆',
        'unlocked': level >= 10,
      },
      {
        'title': 'Usta',
        'desc': '500 kelime öğren',
        'icon': '👑',
        'unlocked': totalWords >= 500,
      },
    ];
  }

  /// Online durumu
  bool get isOnline => _offlineSyncService.isOnline;

  /// Yeni kelime ekle (Proxy to OfflineSyncService)
  Future<Word?> createWord({
    required String english,
    required String turkish,
    required DateTime addedDate,
    String difficulty = 'easy',
  }) async {
    return await _offlineSyncService.createWord(
      english: english,
      turkish: turkish,
      addedDate: addedDate,
      difficulty: difficulty,
    );
  }

  /// Kelimeye cümle ekle (Proxy to OfflineSyncService)
  Future<Word?> addSentenceToWord({
    required int wordId,
    required String sentence,
    required String translation,
    String difficulty = 'easy',
  }) async {
    return await _offlineSyncService.addSentenceToWord(
      wordId: wordId,
      sentence: sentence,
      translation: translation,
      difficulty: difficulty,
    );
  }

  /// Senkronizasyon yap
  Future<bool> syncWithServer() async {
    return await _offlineSyncService.syncWithServer();
  }
}

