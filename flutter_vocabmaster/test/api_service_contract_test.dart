import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/sentence_practice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().saveSession('test_token', 'test_refresh', {
      'id': 4,
      'userId': 4,
      'email': 'api-contract@test.local',
      'displayName': 'API Contract',
      'userTag': '#00004',
      'role': 'USER',
    });
  });
  const testBaseUrl = 'http://localhost:8080/api';

  group('ApiService Contract Tests', () {
    test('addSentenceToWord hits correct endpoint with payload', () async {
      final mockWord = {
        'id': 10,
        'englishWord': 'Focus',
        'turkishMeaning': 'Odak',
        'learnedDate': '2024-01-01',
        'difficulty': 'easy',
        'sentences': [
          {
            'id': 55,
            'sentence': 'Stay focused.',
            'translation': 'Odakli kal.',
            'wordId': 10,
            'difficulty': 'easy',
          }
        ],
      };

      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$testBaseUrl/words/10/sentences');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['sentence'], 'Stay focused.');
        expect(body['translation'], 'Odakli kal.');
        expect(body['difficulty'], 'easy');

        return http.Response(json.encode(mockWord), 201);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final word = await api.addSentenceToWord(
        wordId: 10,
        sentence: 'Stay focused.',
        translation: 'Odakli kal.',
        difficulty: 'easy',
      );

      expect(word, isA<Word>());
      expect(word.sentences.length, 1);
      expect(word.sentences.first.id, 55);
    });

    test('deleteSentenceFromWord hits correct endpoint', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), '$testBaseUrl/words/10/sentences/77');
        return http.Response('', 204);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      await api.deleteSentenceFromWord(10, 77);
    });

    test('deleteSentenceFromWord treats 404 as idempotent success', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), '$testBaseUrl/words/10/sentences/77');
        return http.Response('', 404);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      await api.deleteSentenceFromWord(10, 77);
    });

    test('deleteSentence treats 404 as idempotent success', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), '$testBaseUrl/sentences/123');
        return http.Response('', 404);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      await api.deleteSentence('123');
    });

    test('createSentence uses expected payload and maps response', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$testBaseUrl/sentences');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['englishSentence'], 'Hello world');
        expect(body['turkishTranslation'], 'Merhaba dunya');
        expect(body['difficulty'], 'EASY');
        expect(body['createdDate'], isA<String>());

        return http.Response(
          json.encode({
            'id': 12,
            'englishSentence': 'Hello world',
            'turkishTranslation': 'Merhaba dunya',
            'difficulty': 'EASY',
            'createdDate': '2024-01-02',
          }),
          201,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final sentence = await api.createSentence(
        englishSentence: 'Hello world',
        turkishTranslation: 'Merhaba dunya',
        difficulty: 'easy',
      );

      expect(sentence, isA<SentencePractice>());
      expect(sentence.id, 'practice_12');
      expect(sentence.source, 'practice');
    });

    test('getWordsByDate formats date and hits correct endpoint', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), '$testBaseUrl/words/date/2024-03-10');
        return http.Response(json.encode([]), 200);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final words = await api.getWordsByDate(DateTime(2024, 3, 10));
      expect(words, isA<List<Word>>());
      expect(words, isEmpty);
    });

    test('getSentenceStats returns a map when OK', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), '$testBaseUrl/sentences/stats');
        return http.Response(json.encode({'total': 7}), 200);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final stats = await api.getSentenceStats();
      expect(stats['total'], 7);
    });

    test('chatbotQuotaStatus hits correct endpoint and parses payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), '$testBaseUrl/chatbot/quota/status');
        return http.Response(
          json.encode({
            'success': true,
            'tokenLimit': 50000,
            'tokensUsed': 5000,
            'tokensRemaining': 45000,
            'remainingPercent': 90.0,
          }),
          200,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final quota = await api.chatbotQuotaStatus();

      expect(quota['success'], true);
      expect(quota['tokenLimit'], 50000);
      expect(quota['tokensUsed'], 5000);
      expect(quota['tokensRemaining'], 45000);
    });

    test('chatbotQuotaStatus maps 429 payload to ApiQuotaExceededException', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), '$testBaseUrl/chatbot/quota/status');
        return http.Response(
          json.encode({
            'error': 'Gunluk AI hakkiniz bitti.',
            'retryAfterSeconds': 123,
            'reason': 'daily-token-quota',
            'tokenLimit': 50000,
            'tokensUsed': 50000,
            'tokensRemaining': 0,
          }),
          429,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);

      expect(
        api.chatbotQuotaStatus(),
        throwsA(
          isA<ApiQuotaExceededException>()
              .having((e) => e.reason, 'reason', 'daily-token-quota')
              .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 123)
              .having((e) => e.tokenLimit, 'tokenLimit', 50000)
              .having((e) => e.tokensRemaining, 'tokensRemaining', 0),
        ),
      );
    });
  });
}
