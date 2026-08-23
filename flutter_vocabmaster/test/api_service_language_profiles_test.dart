import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';

/// The language-profile and meaning endpoints are new; the word and sentence
/// endpoints the shipped client calls must keep sending exactly what they sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const String testBaseUrl = 'http://localhost:8080/api';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthService().saveSession('test_token', 'test_refresh', {
      'id': 4,
      'userId': 4,
      'email': 'profiles@test.local',
      'displayName': 'Profiles',
      'userTag': '#00004',
      'role': 'USER',
    });
  });

  Map<String, dynamic> wordBody({int id = 1}) => {
        'id': id,
        'englishWord': 'insight',
        'turkishMeaning': 'içgörü',
        'learnedDate': '2026-08-23',
        'difficulty': 'easy',
        'meanings': [
          {'id': 11, 'translation': 'içgörü', 'position': 0},
        ],
        'languageProfileId': 3,
        'origin': 'manual',
        'sentences': [],
      };

  test('createWord omits "meanings" when none are given (old wire shape)',
      () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      sent = json.decode(request.body) as Map<String, dynamic>;
      return http.Response(json.encode(wordBody()), 201);
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    final word = await api.createWord(
      english: 'insight',
      turkish: 'içgörü',
      addedDate: DateTime(2026, 8, 23),
    );

    expect(sent.containsKey('meanings'), isFalse);
    expect(sent['turkishMeaning'], 'içgörü');
    expect(word.meanings.single.translation, 'içgörü');
    expect(word.languageProfileId, 3);
  });

  test('createWord sends cleaned meanings when given', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      sent = json.decode(request.body) as Map<String, dynamic>;
      return http.Response(json.encode(wordBody()), 201);
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    await api.createWord(
      english: 'insight',
      turkish: 'içgörü, kavrayış',
      addedDate: DateTime(2026, 8, 23),
      meanings: [
        {'translation': ' içgörü '},
        {'translation': 'kavrayış', 'definition': 'deep understanding'},
        {'translation': '   '},
      ],
    );

    expect(sent['meanings'], [
      {'translation': 'içgörü'},
      {'translation': 'kavrayış', 'definition': 'deep understanding'},
    ]);
  });

  test('addSentenceToWord sends meaningId only when set', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      bodies.add(json.decode(request.body) as Map<String, dynamic>);
      return http.Response(json.encode(wordBody()), 201);
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    await api.addSentenceToWord(
      wordId: 1,
      sentence: 'She had a sudden insight.',
      translation: 'Aniden bir içgörü yaşadı.',
    );
    await api.addSentenceToWord(
      wordId: 1,
      sentence: 'She had a sudden insight.',
      translation: 'Aniden bir içgörü yaşadı.',
      meaningId: 11,
    );

    expect(bodies[0].containsKey('meaningId'), isFalse);
    expect(bodies[1]['meaningId'], 11);
  });

  test('getLanguageProfiles parses the list', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), '$testBaseUrl/language-profiles');
      expect(request.headers['X-User-Id'], '4');
      return http.Response(
        json.encode([
          {
            'id': 3,
            'sourceLanguage': 'Turkish',
            'targetLanguage': 'English',
            'level': 'B1',
            'learningGoal': null,
            'isActive': true,
            'createdAt': '2026-08-23T10:00:00',
          }
        ]),
        200,
      );
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    final profiles = await api.getLanguageProfiles();

    expect(profiles.single.id, 3);
    expect(profiles.single.isActive, isTrue);
    expect(profiles.single.targetLanguage, 'English');
  });

  test('createLanguageProfile surfaces 409 as ApiConflictException', () async {
    final client = MockClient((request) async {
      return http.Response(
        json.encode({'message': 'Profile for English already exists'}),
        409,
      );
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    expect(
      () => api.createLanguageProfile(
        sourceLanguage: 'Turkish',
        targetLanguage: 'English',
      ),
      throwsA(isA<ApiConflictException>()),
    );
  });

  test('activateLanguageProfile posts to /activate and tolerates an empty body',
      () async {
    String? method;
    String? path;
    final client = MockClient((request) async {
      method = request.method;
      path = request.url.path;
      return http.Response('', 204);
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    final result = await api.activateLanguageProfile(3);

    expect(method, 'POST');
    expect(path, '/api/language-profiles/3/activate');
    expect(result, isNull);
  });

  test('deleteWordMeaning turns the last-meaning 400 into its own exception',
      () async {
    final client = MockClient((request) async {
      return http.Response(
        json.encode({'message': 'A word must keep at least one meaning'}),
        400,
      );
    });
    final api = ApiService(client: client, baseUrl: testBaseUrl);

    expect(
      () => api.deleteWordMeaning(wordId: 1, meaningId: 11),
      throwsA(isA<ApiLastMeaningException>()),
    );
  });
}
