import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/word.dart';
import '../models/sentence_practice.dart';
import '../config/app_config.dart';
import 'analytics_service.dart';
import 'auth_service.dart';
import 'locale_text_service.dart';

class ApiService {
  final http.Client client;
  final String? _testBaseUrl;
  final AuthService _authService;
  static Future<bool>? _refreshInFlight;

  ApiService({http.Client? client, String? baseUrl, AuthService? authService})
      : client = client ?? http.Client(),
        _testBaseUrl = baseUrl,
        _authService = authService ?? AuthService();

  Future<String> get baseUrl async {
    if (_testBaseUrl != null) return _testBaseUrl!;
    return await AppConfig.apiBaseUrl;
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }

    final token = await _authService.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final userId = await _authService.getUserId();
    if (userId != null && userId > 0) {
      headers['X-User-Id'] = userId.toString();
    }

    final deviceId = await _authService.getOrCreateDeviceId();
    if (deviceId.isNotEmpty) {
      headers['X-Device-Id'] = deviceId;
    }

    return headers;
  }

  Future<Map<String, String>> _protectedHeaders({bool json = false}) async {
    final headers = await _headers(json: json);
    final hasAuth = headers.containsKey('Authorization');
    final hasUserId = headers.containsKey('X-User-Id');
    if (!hasAuth || !hasUserId) {
      throw ApiUnauthorizedException(
        message: 'Oturum bulunamadi. Lutfen yeniden giris yapin.',
        reason: 'missing-auth-context',
      );
    }
    return headers;
  }

  Future<http.Response> _withProtectedRetry(
    Future<http.Response> Function(Map<String, String> headers) send, {
    bool json = false,
  }) async {
    var headers = await _protectedHeaders(json: json);
    var response = await send(headers);
    if (response.statusCode != 401) {
      return response;
    }

    final refreshed = await _tryRefreshSessionCoalesced();
    if (!refreshed) {
      throw _unauthorizedFromResponse(response);
    }

    headers = await _protectedHeaders(json: json);
    response = await send(headers);
    if (response.statusCode == 401) {
      throw _unauthorizedFromResponse(response);
    }
    return response;
  }

  Future<http.Response> _withAiRetry(
    Future<http.Response> Function(Map<String, String> headers) send, {
    required String feature,
    bool json = false,
  }) async {
    final response = await _withProtectedRetry(send, json: json);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      unawaited(AnalyticsService.logFirstAiUse(feature: feature));
    }
    return response;
  }

  Map<String, String> _learningLanguageProfile() {
    return {
      'sourceLanguage': 'Turkish',
      'targetLanguage': 'English',
      'feedbackLanguage': LocaleTextService.isTurkish ? 'Turkish' : 'English',
    };
  }

  Future<void> registerPushToken({
    required String token,
    required String platform,
    String? deviceId,
    String? appVersion,
    String? locale,
    bool dailyRemindersEnabled = false,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw ArgumentError('Push token cannot be empty');
    }

    final url = await baseUrl;
    final response = await _withProtectedRetry(
      (headers) => client.post(
        Uri.parse('$url/push-tokens'),
        headers: headers,
        body: json.encode({
          'token': trimmedToken,
          'platform': platform,
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
          if (appVersion != null && appVersion.isNotEmpty)
            'appVersion': appVersion,
          if (locale != null && locale.isNotEmpty) 'locale': locale,
          'dailyRemindersEnabled': dailyRemindersEnabled.toString(),
        }),
      ),
      json: true,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to register push token: ${response.statusCode}');
    }
  }

  Future<bool> _tryRefreshSessionCoalesced() async {
    final current = _refreshInFlight;
    if (current != null) {
      return current;
    }

    final refreshFuture = _tryRefreshSessionOnce();
    _refreshInFlight = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_refreshInFlight, refreshFuture)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _tryRefreshSessionOnce() async {
    try {
      final refreshToken = await _authService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      final url = await baseUrl;
      final deviceId = await _authService.getOrCreateDeviceId();
      final refreshResponse = await client.post(
        Uri.parse('$url/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: json.encode({
          'refreshToken': refreshToken,
          'deviceInfo': 'Flutter Mobile App',
          'deviceId': deviceId,
        }),
      );

      if (refreshResponse.statusCode != 200) {
        return false;
      }

      final decoded = json.decode(refreshResponse.body);
      if (decoded is! Map) {
        return false;
      }
      final payload = Map<String, dynamic>.from(decoded);
      final newAccessToken =
          (payload['accessToken'] ?? payload['sessionToken'])?.toString();
      final newRefreshToken =
          (payload['refreshToken'] ?? refreshToken).toString();
      if (newAccessToken == null || newAccessToken.isEmpty) {
        return false;
      }

      final currentUser = Map<String, dynamic>.from(
          await _authService.getUser() ?? <String, dynamic>{});
      final refreshedUserId = _toNullableInt(payload['userId']);
      if (refreshedUserId != null && refreshedUserId > 0) {
        currentUser['id'] = refreshedUserId;
        currentUser['userId'] = refreshedUserId;
      }
      currentUser['role'] = (payload['role'] ?? currentUser['role'] ?? 'USER');
      currentUser['email'] = currentUser['email'] ?? '';
      currentUser['displayName'] = currentUser['displayName'] ?? 'User';
      currentUser['userTag'] = currentUser['userTag'] ?? '#00000';

      await _authService.saveSession(
        newAccessToken,
        newRefreshToken,
        currentUser,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==================== WORDS ====================

  Future<List<Word>> getAllWords() async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.get(
          Uri.parse('$url/words'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Word.fromJson(json)).toList();
      }
      throw Exception('Failed to load words: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching words: $e');
      return [];
    }
  }

  Future<Word> getWordById(int id) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.get(
          Uri.parse('$url/words/$id'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        return Word.fromJson(json.decode(response.body));
      }
      throw Exception('Failed to load word: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error fetching word: $e');
    }
  }

  Future<List<String>> getAllDistinctDates() async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.get(
          Uri.parse('$url/words/dates'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<String>();
      }
      throw Exception('Failed to load dates: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching dates: $e');
      return [];
    }
  }

  Future<List<Word>> getWordsByDate(DateTime date) async {
    try {
      final url = await baseUrl;
      final dateStr = date.toIso8601String().split('T')[0];
      final response = await _withProtectedRetry(
        (headers) => client.get(
          Uri.parse('$url/words/date/$dateStr'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Word.fromJson(json)).toList();
      }
      throw Exception('Failed to load words for date: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching words by date: $e');
      return [];
    }
  }

  Future<Word> createWord({
    required String english,
    required String turkish,
    required DateTime addedDate,
    String difficulty = 'easy',
  }) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.post(
          Uri.parse('$url/words'),
          headers: headers,
          body: json.encode({
            'englishWord': english,
            'turkishMeaning': turkish,
            'learnedDate': addedDate.toIso8601String().split('T')[0],
            'notes': '',
            'difficulty': difficulty,
          }),
        ),
        json: true,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Word.fromJson(json.decode(response.body));
      }
      throw Exception('Failed to create word: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error creating word: $e');
    }
  }

  Future<void> deleteWord(int id) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.delete(
          Uri.parse('$url/words/$id'),
          headers: headers,
        ),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        throw Exception('Failed to delete word: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting word: $e');
    }
  }

  Future<Word> addSentenceToWord({
    required int wordId,
    required String sentence,
    required String translation,
    String difficulty = 'easy',
  }) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.post(
          Uri.parse('$url/words/$wordId/sentences'),
          headers: headers,
          body: json.encode({
            'sentence': sentence,
            'translation': translation,
            'difficulty': difficulty,
          }),
        ),
        json: true,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Word.fromJson(json.decode(response.body));
      }
      throw Exception('Failed to add sentence: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error adding sentence: $e');
    }
  }

  Future<void> deleteSentenceFromWord(int wordId, int sentenceId) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.delete(
          Uri.parse('$url/words/$wordId/sentences/$sentenceId'),
          headers: headers,
        ),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        throw Exception('Failed to delete sentence: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting sentence: $e');
    }
  }

  Future<Word> submitWordReview({
    required int wordId,
    required int quality,
  }) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.post(
          Uri.parse('$url/srs/submit-review'),
          headers: headers,
          body: json.encode({
            'wordId': wordId,
            'quality': quality,
          }),
        ),
        json: true,
      );
      if (response.statusCode == 200) {
        return Word.fromJson(json.decode(response.body));
      }
      throw Exception('Failed to submit review: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error submitting review: $e');
    }
  }
  // ==================== SENTENCES ====================

  // ==================== DAILY CONTENT ====================

  Future<List<Map<String, dynamic>>> getDailyWords() async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.get(
          Uri.parse('$url/content/daily-words'),
          headers: headers,
        ),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        if (decoded is Map && decoded['words'] is List) {
          return List<Map<String, dynamic>>.from(decoded['words']);
        }
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
        return [];
      }

      throw Exception('Failed to load daily words: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching daily words: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getDailyReading({
    required String level,
  }) async {
    final url = await baseUrl;
    final response = await _withProtectedRetry(
      (headers) => client.get(
        Uri.parse('$url/content/daily-reading?level=$level'),
        headers: headers,
      ),
    );

    if (response.statusCode == 200) {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map && decoded['data'] is Map) {
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Daily reading yüklenemedi: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getDailyWritingTopic({
    required String level,
  }) async {
    final url = await baseUrl;
    final response = await _withProtectedRetry(
      (headers) => client.get(
        Uri.parse('$url/content/daily-writing-topic?level=$level'),
        headers: headers,
      ),
    );

    if (response.statusCode == 200) {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map && decoded['data'] is Map) {
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Daily writing konusu yüklenemedi: ${response.statusCode}');
  }

  Future<List<SentencePractice>> getAllSentences() async {
    final url = await baseUrl;
    final response = await _withProtectedRetry(
      (headers) => client.get(
        // Pull the largest page allowed by backend to make local reconciliation safer.
        Uri.parse('$url/sentences?page=0&size=200'),
        headers: headers,
      ),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => SentencePractice.fromJson(json)).toList();
    }
    throw Exception('Failed to load sentences: ${response.statusCode}');
  }

  Future<SentencePractice> createSentence({
    required String englishSentence,
    required String turkishTranslation,
    required String difficulty,
  }) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.post(
          Uri.parse('$url/sentences'),
          headers: headers,
          body: json.encode({
            'englishSentence': englishSentence,
            'turkishTranslation': turkishTranslation,
            'difficulty': difficulty.toUpperCase(),
            'createdDate': DateTime.now().toIso8601String().split('T')[0],
          }),
        ),
        json: true,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        return SentencePractice.fromJson({
          'id': 'practice_${responseData['id']}',
          'englishSentence': responseData['englishSentence'],
          'turkishTranslation': responseData['turkishTranslation'],
          'difficulty': responseData['difficulty'],
          'createdDate': responseData['createdDate'],
          'source': 'practice',
        });
      }
      throw Exception('Failed to create sentence: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error creating sentence: $e');
    }
  }

  Future<void> deleteSentence(String id) async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.delete(
          Uri.parse('$url/sentences/$id'),
          headers: headers,
        ),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        throw Exception('Failed to delete sentence: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting sentence: $e');
    }
  }

  Future<Map<String, dynamic>> getSentenceStats() async {
    try {
      final url = await baseUrl;
      final response = await _withProtectedRetry(
        (headers) => client.get(
          Uri.parse('$url/sentences/stats'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('Failed to load stats: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      return {};
    }
  }

  // ==================== AI (CHATBOT) ====================

  /// Thrown when backend returns HTTP 429 for AI endpoints (daily quota or rate limit).
  static ApiQuotaExceededException _quotaFromResponse(http.Response response) {
    try {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        return ApiQuotaExceededException(
          message: (map['error'] ?? 'Günlük AI hakkınız bitti.').toString(),
          retryAfterSeconds: _toNullableInt(map['retryAfterSeconds']),
          reason: map['reason']?.toString(),
          tokenLimit: _toNullableInt(map['tokenLimit']),
          tokensUsed: _toNullableInt(map['tokensUsed']),
          tokensRemaining: _toNullableInt(map['tokensRemaining']),
          banLevel: _toNullableInt(map['banLevel']),
          nextBanSeconds: _toNullableInt(map['nextBanSeconds']),
          abuseWarning: map['abuseWarning']?.toString(),
        );
      }
    } catch (_) {
      // ignore
    }
    return ApiQuotaExceededException(
      message: 'Günlük AI hakkınız bitti. Lütfen daha sonra tekrar deneyin.',
    );
  }

  /// Thrown when backend requires subscription upgrade for AI endpoints.
  static ApiUpgradeRequiredException _upgradeFromResponse(
      http.Response response) {
    try {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        return ApiUpgradeRequiredException(
          message:
              (map['error'] ?? 'AI özelliği bu hesapta devre dışı.').toString(),
          reason: map['reason']?.toString(),
          upgradeRequired: map['upgradeRequired'] == true,
        );
      }
    } catch (_) {
      // ignore
    }
    return ApiUpgradeRequiredException(
      message: 'AI özelliği için Premium plana geçiş gerekli.',
      reason: 'ai-access-disabled',
      upgradeRequired: true,
    );
  }

  static ApiUnauthorizedException _unauthorizedFromResponse(
      http.Response response) {
    try {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final message = (map['message'] ??
                map['error'] ??
                'Oturumunuzun süresi doldu. Lütfen yeniden giriş yapın.')
            .toString();
        return ApiUnauthorizedException(
          message: message,
          reason: map['reason']?.toString(),
          statusCode: response.statusCode,
        );
      }
    } catch (_) {
      // ignore
    }
    return ApiUnauthorizedException(
      message: 'Oturumunuzun süresi doldu. Lütfen yeniden giriş yapın.',
      reason: 'unauthorized',
      statusCode: response.statusCode,
    );
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Future<Map<String, dynamic>> chatbotQuotaStatus() async {
    final url = await baseUrl;
    final response = await _withProtectedRetry(
      (headers) => client.get(
        Uri.parse('$url/chatbot/quota/status'),
        headers: headers,
      ),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('AI token durumu alınamadı: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotGenerateSentences({
    required String word,
    List<String> levels = const ['B1'],
    List<String> lengths = const ['medium'],
    bool checkGrammar = false,
    bool fresh = false,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/generate-sentences'),
        headers: headers,
        body: json.encode({
          'word': word,
          'levels': levels,
          'lengths': lengths,
          'checkGrammar': checkGrammar,
          'fresh': fresh,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'generate_sentences',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('AI cümle üretimi başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotSaveWordToToday({
    required String englishWord,
    List<String> meanings = const [],
    List<String> sentences = const [],
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/save-to-today'),
        headers: headers,
        body: json.encode({
          'englishWord': englishWord,
          'meanings': meanings,
          'sentences': sentences,
        }),
      ),
      feature: 'save_word_to_today',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Kelime kaydetme başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotCheckTranslation({
    required String direction, // EN_TO_TR or TR_TO_EN
    required String userTranslation,
    String? englishSentence,
    String? turkishSentence,
    String? referenceEnglishSentence,
  }) async {
    final url = await baseUrl;
    final body = <String, dynamic>{
      'direction': direction,
      'userTranslation': userTranslation,
      ..._learningLanguageProfile(),
    };
    if (englishSentence != null) body['englishSentence'] = englishSentence;
    if (turkishSentence != null) body['turkishSentence'] = turkishSentence;
    if (referenceEnglishSentence != null &&
        (englishSentence == null || englishSentence.isEmpty)) {
      // Backend uses `englishSentence` as optional reference for TR_TO_EN checks.
      body['englishSentence'] = referenceEnglishSentence;
    }

    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/check-translation'),
        headers: headers,
        body: json.encode(body),
      ),
      feature: 'check_translation',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('AI çeviri kontrolü başarısız: ${response.statusCode}');
  }

  Future<String> chatbotChat({
    required String message,
    String? scenario,
    String? scenarioContext,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/chat'),
        headers: headers,
        body: json.encode({
          'message': message,
          if (scenario != null) 'scenario': scenario,
          if (scenarioContext != null) 'scenarioContext': scenarioContext,
        }),
      ),
      feature: 'chat',
      json: true,
    );
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['response'] != null) {
        return decoded['response'].toString();
      }
      return '';
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('AI sohbet başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotGenerateSpeakingTestQuestions({
    required String testType,
    required String part,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/speaking-test/generate-questions'),
        headers: headers,
        body: json.encode({'testType': testType, 'part': part}),
      ),
      feature: 'speaking_test_generate_questions',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('AI speaking soruları başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotEvaluateSpeakingTest({
    required String testType,
    required String question,
    required String responseText,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/speaking-test/evaluate'),
        headers: headers,
        body: json.encode({
          'testType': testType,
          'question': question,
          'response': responseText,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'speaking_test_evaluate',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception(
        'AI speaking değerlendirme başarısız: ${response.statusCode}');
  }

  // ==================== AI (DICTIONARY / READING / WRITING / EXAM) ====================

  Future<Map<String, dynamic>> chatbotDictionaryLookup({
    required String word,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/dictionary/lookup'),
        headers: headers,
        body: json.encode({
          'word': word,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'dictionary_lookup',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Sözlük araması başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotDictionaryLookupDetailed({
    required String word,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/dictionary/lookup-detailed'),
        headers: headers,
        body: json.encode({
          'word': word,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'dictionary_lookup_detailed',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Detayli sözlük araması başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotDictionaryExplainWordInSentence({
    required String word,
    required String sentence,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/dictionary/explain'),
        headers: headers,
        body: json.encode({
          'word': word,
          'sentence': sentence,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'dictionary_explain',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Sözlük açıklama başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotDictionaryGenerateSpecificSentence({
    required String word,
    required String translation,
    required String context,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/dictionary/generate-specific-sentence'),
        headers: headers,
        body: json.encode({
          'word': word,
          'translation': translation,
          'context': context,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'dictionary_generate_specific_sentence',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Örnek cümle üretimi başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotGenerateReadingPassage({
    required String level,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/reading/generate'),
        headers: headers,
        body: json.encode({
          'level': level,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'reading_generate',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Reading üretimi başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotGenerateWritingTopic({
    required String level,
    required String wordCount,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/writing/generate-topic'),
        headers: headers,
        body: json.encode({
          'level': level,
          'wordCount': wordCount,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'writing_generate_topic',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Writing konusu üretimi başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotEvaluateWriting({
    required String text,
    required String level,
    required Map<String, dynamic> topic,
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/writing/evaluate'),
        headers: headers,
        body: json.encode({
          'text': text,
          'level': level,
          'topic': topic,
          ..._learningLanguageProfile(),
        }),
      ),
      feature: 'writing_evaluate',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Writing değerlendirme başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotGenerateExamBundle({
    required String examType,
    required String category,
    required int questionCount,
    required String userLevel,
    String targetScore = '60-80',
    String mode = 'category',
    String track = 'general',
  }) async {
    final url = await baseUrl;
    final response = await _withAiRetry(
      (headers) => client.post(
        Uri.parse('$url/chatbot/exam/generate'),
        headers: headers,
        body: json.encode({
          'examType': examType,
          'mode': mode,
          'category': category,
          'track': track,
          'questionCount': questionCount,
          'userLevel': userLevel,
          'targetScore': targetScore,
        }),
      ),
      feature: 'exam_generate',
      json: true,
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    if (response.statusCode == 403) {
      throw _upgradeFromResponse(response);
    }
    throw Exception('Sınav üretimi başarısız: ${response.statusCode}');
  }
}

class ApiQuotaExceededException implements Exception {
  final String message;
  final int? retryAfterSeconds;
  final String? reason;
  final int? tokenLimit;
  final int? tokensUsed;
  final int? tokensRemaining;
  final int? banLevel;
  final int? nextBanSeconds;
  final String? abuseWarning;

  ApiQuotaExceededException({
    required this.message,
    this.retryAfterSeconds,
    this.reason,
    this.tokenLimit,
    this.tokensUsed,
    this.tokensRemaining,
    this.banLevel,
    this.nextBanSeconds,
    this.abuseWarning,
  });

  @override
  String toString() => message;
}

class ApiUpgradeRequiredException implements Exception {
  final String message;
  final String? reason;
  final bool upgradeRequired;

  ApiUpgradeRequiredException({
    required this.message,
    this.reason,
    this.upgradeRequired = true,
  });

  @override
  String toString() => message;
}

class ApiUnauthorizedException implements Exception {
  final String message;
  final String? reason;
  final int? statusCode;

  ApiUnauthorizedException({
    required this.message,
    this.reason,
    this.statusCode,
  });

  @override
  String toString() => message;
}
