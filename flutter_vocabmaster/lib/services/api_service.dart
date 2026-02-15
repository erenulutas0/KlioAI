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
}
