import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/sentence_practice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    LocaleTextService.setAppLocale(const Locale('tr'));
    LearningLanguageService.setSourceLanguage('Turkish');
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
    test('registerPushToken posts token metadata', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$testBaseUrl/push-tokens');
        expect(request.headers['Authorization'], 'Bearer test_token');
        expect(request.headers['X-User-Id'], '4');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['token'], 'fcm-token-123');
        expect(body['platform'], 'android');
        expect(body['deviceId'], 'device-1');
        expect(body['locale'], 'en');
        expect(body['dailyRemindersEnabled'], 'true');

        return http.Response(json.encode({'registered': true}), 200);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      await api.registerPushToken(
        token: 'fcm-token-123',
        platform: 'android',
        deviceId: 'device-1',
        locale: 'en',
        dailyRemindersEnabled: true,
      );
    });

    test(
        'notification preferences load and update use push preference endpoints',
        () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount += 1;
        expect(request.headers['Authorization'], 'Bearer test_token');
        expect(request.headers['X-User-Id'], '4');

        if (callCount == 1) {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            '$testBaseUrl/push-tokens/preferences',
          );
          return http.Response(
            json.encode({
              'dailyRemindersEnabled': true,
              'streakGuardEnabled': false,
              'subscriptionAlertsEnabled': true,
            }),
            200,
          );
        }

        expect(request.method, 'PUT');
        expect(
          request.url.toString(),
          '$testBaseUrl/push-tokens/preferences',
        );
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['dailyRemindersEnabled'], true);
        expect(body['streakGuardEnabled'], true);
        return http.Response(json.encode(body), 200);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final loaded = await api.getNotificationPreferences();
      expect(loaded['dailyRemindersEnabled'], true);

      final updated = await api.updateNotificationPreferences({
        'dailyRemindersEnabled': true,
        'streakGuardEnabled': true,
      });
      expect(updated['streakGuardEnabled'], true);
    });

    test('chatbotGenerateSentences sends persisted learning language profile',
        () async {
      LearningLanguageService.setSourceLanguage('English');
      LocaleTextService.setAppLocale(const Locale('en'));

      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
            request.url.toString(), '$testBaseUrl/chatbot/generate-sentences');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['word'], 'focus');
        expect(body['direction'], 'TR_TO_EN');
        expect(body['sourceLanguage'], 'English');
        expect(body['targetLanguage'], 'English');
        expect(body['feedbackLanguage'], 'English');

        return http.Response(json.encode({'sentences': []}), 200);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final result = await api.chatbotGenerateSentences(
        word: 'focus',
        direction: 'TR_TO_EN',
      );

      expect(result['sentences'], isA<List<dynamic>>());
    });

    test('chatbotGenerateSentences sends neutral direction for Spanish source',
        () async {
      LearningLanguageService.setSourceLanguage('Spanish');
      LearningLanguageService.setEnglishLevel('B2');
      LearningLanguageService.setLearningGoal('Travel');
      LocaleTextService.setAppLocale(const Locale('en'));

      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
            request.url.toString(), '$testBaseUrl/chatbot/generate-sentences');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['word'], 'delay');
        expect(body['direction'], 'SOURCE_TO_TARGET');
        expect(body['sourceLanguage'], 'Spanish');
        expect(body['targetLanguage'], 'English');
        expect(body['feedbackLanguage'], 'English');
        expect(body['englishLevel'], 'B2');
        expect(body['learningGoal'], 'Travel');

        return http.Response(json.encode({'sentences': []}), 200);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final result = await api.chatbotGenerateSentences(
        word: 'delay',
        direction: 'SOURCE_TO_TARGET',
      );

      expect(result['sentences'], isA<List<dynamic>>());
    });

    test('chatbotTranscribeSpeech sends multipart audio payload', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('klioai_test_audio');
      final audioFile = File('${tempDir.path}/speech.m4a');
      await audioFile.writeAsBytes([1, 2, 3, 4]);

      try {
        final mockClient = MockClient((request) async {
          expect(request.method, 'POST');
          expect(
              request.url.toString(), '$testBaseUrl/chatbot/speech/transcribe');
          expect(request.headers['Authorization'], 'Bearer test_token');
          expect(request.headers['X-User-Id'], '4');
          expect(
              request.headers['content-type'], contains('multipart/form-data'));

          final body = latin1.decode(request.bodyBytes);
          expect(body, contains('name="durationMs"'));
          expect(body, contains('2100'));
          expect(body, contains('name="locale"'));
          expect(body, contains('en_US'));
          expect(body, contains('name="audio"; filename="speech.m4a"'));

          return http.Response(
            json.encode({
              'success': true,
              'text': 'I want to practice speaking.',
              'model': 'whisper-large-v3-turbo',
            }),
            200,
          );
        });

        final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
        final result = await api.chatbotTranscribeSpeech(
          audioPath: audioFile.path,
          durationMs: 2100,
        );

        expect(result['text'], 'I want to practice speaking.');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('chatbotGeneratePronunciationTexts sends focus words and profile',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          '$testBaseUrl/chatbot/pronunciation/generate-texts',
        );
        expect(request.headers['Authorization'], 'Bearer test_token');
        expect(request.headers['X-User-Id'], '4');

        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['level'], 'B1');
        expect(body['focusWords'], ['delay', 'focus']);
        expect(body['sourceLanguage'], 'Turkish');
        expect(body['targetLanguage'], 'English');

        return http.Response(
          json.encode({
            'texts': [
              'The delayed train finally arrived after lunch.',
              'Please focus on the final sound of each word.',
            ],
            'level': 'B1',
          }),
          200,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final result = await api.chatbotGeneratePronunciationTexts(
        level: 'B1',
        focusWords: const ['delay', 'focus'],
      );

      expect(result['texts'], isA<List<dynamic>>());
    });

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

    test('chatbotQuotaStatus hits correct endpoint and parses payload',
        () async {
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

    test('chatbotQuotaStatus maps 429 payload to ApiQuotaExceededException',
        () async {
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

    test(
        'chatbotGenerateSentences maps 403 payload to ApiUpgradeRequiredException',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
            request.url.toString(), '$testBaseUrl/chatbot/generate-sentences');
        return http.Response(
          json.encode({
            'error': 'AI access is disabled for current plan.',
            'reason': 'ai-access-disabled',
            'upgradeRequired': true,
          }),
          403,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);

      expect(
        api.chatbotGenerateSentences(word: 'focus'),
        throwsA(
          isA<ApiUpgradeRequiredException>()
              .having((e) => e.reason, 'reason', 'ai-access-disabled')
              .having((e) => e.upgradeRequired, 'upgradeRequired', true),
        ),
      );
    });

    test('chatbotDictionaryLookup maps 429 payload through shared AI retry',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          '$testBaseUrl/chatbot/dictionary/lookup',
        );
        return http.Response(
          json.encode({
            'error': 'Gunluk AI hakkiniz bitti.',
            'retryAfterSeconds': 90,
            'reason': 'non-paid-ip-token-quota',
            'tokenLimit': 20000,
            'tokensUsed': 20000,
            'tokensRemaining': 0,
          }),
          429,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);

      expect(
        api.chatbotDictionaryLookup(word: 'focus'),
        throwsA(
          isA<ApiQuotaExceededException>()
              .having((e) => e.reason, 'reason', 'non-paid-ip-token-quota')
              .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 90)
              .having((e) => e.tokenLimit, 'tokenLimit', 20000)
              .having((e) => e.tokensRemaining, 'tokensRemaining', 0),
        ),
      );
    });

    test('chatbotChat maps backend 5xx to ApiAiServiceException', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$testBaseUrl/chatbot/chat');
        return http.Response(
          json.encode({
            'error': 'Failed to get response: provider unavailable',
          }),
          500,
        );
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);

      expect(
        api.chatbotChat(message: 'Can we practice speaking?'),
        throwsA(
          isA<ApiAiServiceException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.feature, 'feature', 'chat'),
        ),
      );
    });

    test(
        'AI request payloads include supported language profile from app locale',
        () async {
      LocaleTextService.setAppLocale(const Locale('en'));
      final seenPaths = <String>[];

      final mockClient = MockClient((request) async {
        seenPaths.add(request.url.path);
        final body = json.decode(request.body) as Map<String, dynamic>;

        expect(body['sourceLanguage'], 'Turkish');
        expect(body['targetLanguage'], 'English');
        expect(body['feedbackLanguage'], 'English');

        if (request.url.path.endsWith('/chatbot/generate-sentences')) {
          expect(body['word'], 'focus');
          return http.Response(
            json.encode({'sentences': [], 'translations': [], 'count': 0}),
            200,
          );
        }

        if (request.url.path.endsWith('/chatbot/dictionary/lookup')) {
          expect(body['word'], 'focus');
          return http.Response(
            json.encode({'word': 'focus', 'meanings': []}),
            200,
          );
        }

        if (request.url.path.endsWith('/chatbot/chat')) {
          expect(body['message'], 'Hello there');
          return http.Response(
            json.encode({'response': 'Hi!', 'timestamp': 0}),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);

      await api.chatbotGenerateSentences(word: 'focus');
      await api.chatbotDictionaryLookup(word: 'focus');
      await api.chatbotChat(message: 'Hello there');

      expect(
        seenPaths,
        containsAll([
          '/api/chatbot/generate-sentences',
          '/api/chatbot/dictionary/lookup',
          '/api/chatbot/chat',
        ]),
      );
    });

    test('chatbotGenerateSentences refreshes token once and retries on 401',
        () async {
      var sentenceCallCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.toString() == '$testBaseUrl/auth/refresh') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['refreshToken'], 'test_refresh');
          return http.Response(
            json.encode({
              'success': true,
              'accessToken': 'rotated_access',
              'refreshToken': 'rotated_refresh',
              'userId': 4,
              'role': 'USER',
            }),
            200,
          );
        }

        if (request.url.toString() ==
            '$testBaseUrl/chatbot/generate-sentences') {
          sentenceCallCount += 1;
          if (sentenceCallCount == 1) {
            expect(request.headers['authorization'], 'Bearer test_token');
            return http.Response(
              json.encode({'error': 'Unauthorized', 'success': false}),
              401,
            );
          }

          expect(request.headers['authorization'], 'Bearer rotated_access');
          return http.Response(
            json.encode({
              'sentences': ['I read books.'],
              'translations': ['Kitap okurum.'],
              'count': 1,
              'cached': false,
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient, baseUrl: testBaseUrl);
      final result = await api.chatbotGenerateSentences(word: 'book');

      expect(sentenceCallCount, 2);
      expect(result['count'], 1);
      expect(result['sentences'][0], 'I read books.');
    });
  });
}
