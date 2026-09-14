import 'dart:convert';
import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// The rating, as it leaves the phone.
///
/// The server's side of this is FeatureRatingControllerTest: these are the same field names
/// from the other end, so a rename on either side fails a test instead of quietly storing
/// ratings with no scene and no note.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const String base = 'http://localhost:8080/api';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    LocaleTextService.setAppLocale(const Locale('tr'));
    LearningLanguageService.setSourceLanguage('Turkish');
    await AuthService().saveSession('test_token', 'test_refresh', <String, dynamic>{
      'id': 4,
      'userId': 4,
      'email': 'ratings@test.local',
      'displayName': 'Ratings',
      'userTag': '#00004',
      'role': 'USER',
    });
  });

  test('a rating is posted with everything the digest reads', () async {
    late http.Request seen;
    final ApiService api = ApiService(
      client: MockClient((http.Request request) async {
        seen = request;
        return http.Response('{"id":1,"feature":"TUTOR","stars":4}', 201);
      }),
      baseUrl: base,
    );

    await api.submitFeatureRating(
      feature: 'TUTOR',
      stars: 4,
      note: '  The replies were long  ',
      sceneId: 'restaurant_order',
      locale: 'tr',
      appVersion: '1.4.1+484',
      context: <String, Object?>{'turns': 6, 'level': 'B1'},
    );

    expect(seen.method, 'POST');
    expect(seen.url.toString(), '$base/feedback/ratings');
    expect(seen.headers['Authorization'], 'Bearer test_token');
    expect(seen.headers['X-User-Id'], '4');
    expect(json.decode(seen.body), <String, Object?>{
      'feature': 'TUTOR',
      'stars': 4,
      'note': 'The replies were long',
      'sceneId': 'restaurant_order',
      'locale': 'tr',
      'appVersion': '1.4.1+484',
      'context': <String, Object?>{'turns': 6, 'level': 'B1'},
    });
  });

  test('what was not given is left out rather than sent empty', () async {
    late http.Request seen;
    final ApiService api = ApiService(
      client: MockClient((http.Request request) async {
        seen = request;
        return http.Response('{}', 201);
      }),
      baseUrl: base,
    );

    await api.submitFeatureRating(
      feature: 'READING',
      stars: 5,
      note: '   ',
      sceneId: '',
      context: <String, Object?>{},
    );

    expect(json.decode(seen.body), <String, Object?>{'feature': 'READING', 'stars': 5});
  });

  test('a rating the server refused is not treated as saved', () async {
    final ApiService api = ApiService(
      client: MockClient((http.Request request) async =>
          http.Response('{"error":"DAILY_LIMIT_REACHED"}', 429)),
      baseUrl: base,
    );

    await expectLater(
      api.submitFeatureRating(feature: 'TUTOR', stars: 5),
      throwsException,
    );
  });
}
