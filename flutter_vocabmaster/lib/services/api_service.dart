import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/word.dart';
import '../models/sentence_practice.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

class ApiService {
  final http.Client client;
  final String? _testBaseUrl;
  final AuthService _authService;

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

    return headers;
  }

  Future<Map<String, String>> _protectedHeaders({bool json = false}) async {
    final headers = await _headers(json: json);
    final hasAuth = headers.containsKey('Authorization');
    final hasUserId = headers.containsKey('X-User-Id');
    if (!hasAuth || !hasUserId) {
      throw Exception('Missing authenticated user context');
    }
    return headers;
  }

  // ==================== WORDS ====================

  Future<List<Word>> getAllWords() async {
    try {
      final url = await baseUrl;
      final response = await client.get(
        Uri.parse('$url/words'),
        headers: await _protectedHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Word.fromJson(json)).toList();
      }
      throw Exception('Failed to load words: ${response.statusCode}');
    } catch (e) {
      print('Error fetching words: $e');
      return [];
    }
  }

  Future<Word> getWordById(int id) async {
    try {
      final url = await baseUrl;
      final response = await client.get(
        Uri.parse('$url/words/$id'),
        headers: await _protectedHeaders(),
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
      final response = await client.get(
        Uri.parse('$url/words/dates'),
        headers: await _protectedHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<String>();
      }
      throw Exception('Failed to load dates: ${response.statusCode}');
    } catch (e) {
      print('Error fetching dates: $e');
      return [];
    }
  }

  Future<List<Word>> getWordsByDate(DateTime date) async {
    try {
      final url = await baseUrl;
      final dateStr = date.toIso8601String().split('T')[0];
      final response = await client.get(
        Uri.parse('$url/words/date/$dateStr'),
        headers: await _protectedHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Word.fromJson(json)).toList();
      }
      throw Exception('Failed to load words for date: ${response.statusCode}');
    } catch (e) {
      print('Error fetching words by date: $e');
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
      final response = await client.post(
        Uri.parse('$url/words'),
        headers: await _protectedHeaders(json: true),
        body: json.encode({
          'englishWord': english,
          'turkishMeaning': turkish,
          'learnedDate': addedDate.toIso8601String().split('T')[0],
          'notes': '',
          'difficulty': difficulty,
        }),
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
      final response = await client.delete(
        Uri.parse('$url/words/$id'),
        headers: await _protectedHeaders(),
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
      final response = await client.post(
        Uri.parse('$url/words/$wordId/sentences'),
        headers: await _protectedHeaders(json: true),
        body: json.encode({
          'sentence': sentence,
          'translation': translation,
          'difficulty': difficulty,
        }),
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
      final response = await client.delete(
        Uri.parse('$url/words/$wordId/sentences/$sentenceId'),
        headers: await _protectedHeaders(),
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

  // ==================== SENTENCES ====================

  // ==================== DAILY CONTENT ====================

  Future<List<Map<String, dynamic>>> getDailyWords() async {
    try {
      final url = await baseUrl;
      final response = await client.get(
        Uri.parse('$url/content/daily-words'),
        headers: await _protectedHeaders(),
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
      print('Error fetching daily words: $e');
      return [];
    }
  }

  Future<List<SentencePractice>> getAllSentences() async {
    final url = await baseUrl;
    final response = await client.get(
      // Pull the largest page allowed by backend to make local reconciliation safer.
      Uri.parse('$url/sentences?page=0&size=200'),
      headers: await _protectedHeaders(),
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
      final response = await client.post(
        Uri.parse('$url/sentences'),
        headers: await _protectedHeaders(json: true),
        body: json.encode({
          'englishSentence': englishSentence,
          'turkishTranslation': turkishTranslation,
          'difficulty': difficulty.toUpperCase(),
          'createdDate': DateTime.now().toIso8601String().split('T')[0],
        }),
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
      final response = await client.delete(
        Uri.parse('$url/sentences/$id'),
        headers: await _protectedHeaders(),
      );
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete sentence: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting sentence: $e');
    }
  }

  Future<Map<String, dynamic>> getSentenceStats() async {
    try {
      final url = await baseUrl;
      final response = await client.get(
        Uri.parse('$url/sentences/stats'),
        headers: await _protectedHeaders(),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('Failed to load stats: ${response.statusCode}');
    } catch (e) {
      print('Error fetching stats: $e');
      return {};
    }
  }

  // ==================== AI (CHATBOT) ====================

  /// Thrown when backend returns HTTP 429 for AI endpoints (daily quota or rate limit).
  static ApiQuotaExceededException _quotaFromResponse(http.Response response) {
    try {
      final dynamic decoded = json.decode(response.body);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded as Map);
        return ApiQuotaExceededException(
          message: (map['error'] ?? 'Günlük AI hakkınız bitti.').toString(),
          retryAfterSeconds: _toNullableInt(map['retryAfterSeconds']),
          reason: map['reason']?.toString(),
          tokenLimit: _toNullableInt(map['tokenLimit']),
          tokensUsed: _toNullableInt(map['tokensUsed']),
          tokensRemaining: _toNullableInt(map['tokensRemaining']),
        );
      }
    } catch (_) {
      // ignore
    }
    return ApiQuotaExceededException(
      message: 'Günlük AI hakkınız bitti. Lütfen daha sonra tekrar deneyin.',
    );
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Future<Map<String, dynamic>> chatbotGenerateSentences({
    required String word,
    List<String> levels = const ['B1'],
    List<String> lengths = const ['medium'],
    bool checkGrammar = false,
  }) async {
    final url = await baseUrl;
    final response = await client.post(
      Uri.parse('$url/chatbot/generate-sentences'),
      headers: await _protectedHeaders(json: true),
      body: json.encode({
        'word': word,
        'levels': levels,
        'lengths': lengths,
        'checkGrammar': checkGrammar,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    throw Exception('AI cümle üretimi başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotSaveWordToToday({
    required String englishWord,
    List<String> meanings = const [],
    List<String> sentences = const [],
  }) async {
    final url = await baseUrl;
    final response = await client.post(
      Uri.parse('$url/chatbot/save-to-today'),
      headers: await _protectedHeaders(json: true),
      body: json.encode({
        'englishWord': englishWord,
        'meanings': meanings,
        'sentences': sentences,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
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
    };
    if (englishSentence != null) body['englishSentence'] = englishSentence;
    if (turkishSentence != null) body['turkishSentence'] = turkishSentence;
    if (referenceEnglishSentence != null &&
        (englishSentence == null || englishSentence.isEmpty)) {
      // Backend uses `englishSentence` as optional reference for TR_TO_EN checks.
      body['englishSentence'] = referenceEnglishSentence;
    }

    final response = await client.post(
      Uri.parse('$url/chatbot/check-translation'),
      headers: await _protectedHeaders(json: true),
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    throw Exception('AI çeviri kontrolü başarısız: ${response.statusCode}');
  }

  Future<String> chatbotChat({
    required String message,
    String? scenario,
    String? scenarioContext,
  }) async {
    final url = await baseUrl;
    final response = await client.post(
      Uri.parse('$url/chatbot/chat'),
      headers: await _protectedHeaders(json: true),
      body: json.encode({
        'message': message,
        if (scenario != null) 'scenario': scenario,
        if (scenarioContext != null) 'scenarioContext': scenarioContext,
      }),
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
    throw Exception('AI sohbet başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotGenerateSpeakingTestQuestions({
    required String testType,
    required String part,
  }) async {
    final url = await baseUrl;
    final response = await client.post(
      Uri.parse('$url/chatbot/speaking-test/generate-questions'),
      headers: await _protectedHeaders(json: true),
      body: json.encode({'testType': testType, 'part': part}),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    throw Exception('AI speaking soruları başarısız: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> chatbotEvaluateSpeakingTest({
    required String testType,
    required String question,
    required String responseText,
  }) async {
    final url = await baseUrl;
    final response = await client.post(
      Uri.parse('$url/chatbot/speaking-test/evaluate'),
      headers: await _protectedHeaders(json: true),
      body: json.encode({
        'testType': testType,
        'question': question,
        'response': responseText,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 429) {
      throw _quotaFromResponse(response);
    }
    throw Exception('AI speaking değerlendirme başarısız: ${response.statusCode}');
  }
}

class ApiQuotaExceededException implements Exception {
  final String message;
  final int? retryAfterSeconds;
  final String? reason;
  final int? tokenLimit;
  final int? tokensUsed;
  final int? tokensRemaining;

  ApiQuotaExceededException({
    required this.message,
    this.retryAfterSeconds,
    this.reason,
    this.tokenLimit,
    this.tokensUsed,
    this.tokensRemaining,
  });

  @override
  String toString() => message;
}
