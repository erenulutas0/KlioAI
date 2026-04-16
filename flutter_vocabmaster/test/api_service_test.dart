import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/models/word.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().saveSession('test_token', 'test_refresh', {
      'id': 4,
      'userId': 4,
      'email': 'api-service@test.local',
      'displayName': 'API Service',
      'userTag': '#00004',
      'role': 'USER',
    });
  });
  group('ApiService Tests', () {
    late ApiService apiService;
    late MockClient mockClient;
    const String testBaseUrl = 'http://localhost:8080/api';

    test('getAllWords returns list of words if call completes successfully',
        () async {
      final mockResponse = [
        {
          "id": 1,
          "englishWord": "Apple",
          "turkishMeaning": "Elma",
          "learnedDate": "2023-01-01",
          "difficulty": "EASY",
          "easeFactor": 2.5,
          "reviewCount": 0
        }
      ];

      mockClient = MockClient((request) async {
        if (request.url.toString() == '$testBaseUrl/words') {
          return http.Response(json.encode(mockResponse), 200);
        }
        return http.Response('Not Found', 404);
      });

      apiService = ApiService(client: mockClient, baseUrl: testBaseUrl);

      final words = await apiService.getAllWords();

      expect(words, isA<List<Word>>());
      expect(words.length, 1);
      expect(words[0].englishWord, 'Apple');
    });

    test('getAllWords returns empty list when exception occurs', () async {
      mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      apiService = ApiService(client: mockClient, baseUrl: testBaseUrl);

      final words = await apiService.getAllWords();

      expect(words, isEmpty);
    });

    test('createWord sends post request and returns word', () async {
      final newWordJson = {
        "id": 2,
        "englishWord": "Banana",
        "turkishMeaning": "Muz",
        "learnedDate": "2023-01-02",
        "difficulty": "EASY"
      };

      mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), '$testBaseUrl/words');

        final body = json.decode(request.body);
        expect(body['englishWord'], 'Banana');

        return http.Response(json.encode(newWordJson), 201);
      });

      apiService = ApiService(client: mockClient, baseUrl: testBaseUrl);

      final word = await apiService.createWord(
          english: "Banana", turkish: "Muz", addedDate: DateTime(2023, 1, 2));

      expect(word.englishWord, 'Banana');
      expect(word.id, 2);
    });

    test('deleteWord sends delete request', () async {
      mockClient = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), '$testBaseUrl/words/100');
        return http.Response('', 204);
      });

      apiService = ApiService(client: mockClient, baseUrl: testBaseUrl);

      await apiService.deleteWord(100);
    });
  });
}
