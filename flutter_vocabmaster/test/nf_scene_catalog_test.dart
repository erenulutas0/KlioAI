import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/services/nf_scenes.dart';
import 'package:vocabmaster/models/voice_model.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';

/// The scene catalog, as the app receives and keeps it.
///
/// The rail used to be a constant of eight. It is the server's catalog now --
/// twenty-five scenes with titles and goals in the learner's language -- so
/// what these pin is the trip: an entry that cannot start a scene is dropped
/// rather than drawn, the opening a conversation shows is the one the server is
/// told it said, and a catalog fetched once is there next time, in its language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await AuthService().saveSession('t', 'r', <String, dynamic>{
      'id': 4,
      'userId': 4,
      'email': 'learner@test.local',
      'displayName': 'Learner',
      'userTag': '#00004',
      'role': 'USER',
    });
  });

  Map<String, Object?> catalog() => <String, Object?>{
        'version': 'abc123',
        'scenes': <Object?>[
          <String, Object?>{
            'id': 'restaurant_order',
            'category': 'daily',
            'icon': 'restaurant',
            'minLevel': 'A1',
            'character': 'Luca',
            'voice': 'ryan',
            'openings': <String>[
              'Good evening! Something to drink while you look?',
              'Hi, welcome! Are you ready to order?',
            ],
            'title': 'Restoranda',
            'goal': 'Bir yemek sipariş et ve hesabı iste.',
          },
          <String, Object?>{'id': '', 'character': 'Nobody', 'openings': <String>['Hello?']},
          <String, Object?>{'id': 'silent', 'character': 'Mute', 'openings': <String>[]},
          <String, Object?>{
            'id': 'from_the_future',
            'category': 'space',
            'icon': 'rocket_someday',
            'character': 'Ada',
            'openings': <String>['Welcome aboard. Is this your first flight?'],
          },
        ],
      };

  ApiService serving(Map<String, Object?> body, {void Function(http.Request)? onRequest}) =>
      ApiService(
        baseUrl: 'http://localhost:8080/api',
        client: MockClient((http.Request request) async {
          onRequest?.call(request);
          return http.Response(
            json.encode(body),
            200,
            headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

  test('an entry becomes a scene with everything the app shows', () {
    final List<NfScene> scenes = NfSceneCatalog.parse(catalog())!;

    // The two that cannot start a scene -- no id, nothing to open with -- are gone.
    expect(scenes.map((NfScene s) => s.id), <String>['restaurant_order', 'from_the_future']);

    final NfScene luca = scenes.first;
    expect(luca.character, 'Luca');
    expect(luca.voice, 'ryan');
    expect(luca.title, 'Restoranda');
    expect(luca.goal, 'Bir yemek sipariş et ve hesabı iste.');
    expect(luca.minLevel, 'A1');
    expect(luca.category, 'daily');
    expect(luca.icon, Icons.restaurant_outlined);

    // A scene added on the server after this build still appears, with the
    // default picture and under its own kind.
    final NfScene ada = scenes.last;
    expect(ada.icon, Icons.theater_comedy_outlined);
    expect(ada.category, 'space');
    expect(ada.goal, isNull);
  });

  test('the opening a conversation shows is the one the server is told it said', () {
    // The server picks openings[variant mod count] too (ScenarioCatalog.openingFor).
    final NfScene luca = NfSceneCatalog.parse(catalog())!.first;

    expect(luca.openingFor(0), 'Good evening! Something to drink while you look?');
    expect(luca.openingFor(1), 'Hi, welcome! Are you ready to order?');
    expect(luca.openingFor(2), 'Good evening! Something to drink while you look?');
    expect(luca.openingFor(null), luca.opening);
  });

  test('anything that is not a catalog is no catalog', () {
    expect(NfSceneCatalog.parse(null), isNull);
    expect(NfSceneCatalog.parse('scenes'), isNull);
    expect(NfSceneCatalog.parse(<String, Object?>{'scenes': 'none'}), isNull);
    expect(NfSceneCatalog.parse(<String, Object?>{'scenes': <Object?>[]}), isNull);
  });

  test('a fetched catalog is kept for next time, in its own language', () async {
    Uri? asked;
    final ApiService api = serving(catalog(), onRequest: (http.Request r) => asked = r.url);

    expect(await NfSceneCatalog.cached('tr'), isNull);

    final List<NfScene>? fresh = await NfSceneCatalog.refresh(api, 'tr');

    expect(asked!.path, '/api/chatbot/scenarios');
    expect(asked!.queryParameters['lang'], 'tr');
    expect(fresh!.first.title, 'Restoranda');
    expect((await NfSceneCatalog.cached('tr'))!.first.title, 'Restoranda');
    expect(await NfSceneCatalog.cached('de'), isNull,
        reason: 'a Turkish catalog is not a German one');
  });

  test('a failed fetch costs nothing that was already there', () async {
    await NfSceneCatalog.refresh(serving(catalog()), 'tr');
    final ApiService failing = ApiService(
      baseUrl: 'http://localhost:8080/api',
      client: MockClient((_) async => http.Response('gone', 404)),
    );

    expect(await NfSceneCatalog.refresh(failing, 'tr'), isNull);
    expect((await NfSceneCatalog.cached('tr'))!.first.id, 'restaurant_order');
  });

  test('every built-in scene speaks in a voice the app can play', () {
    final Set<String> voices =
        VoiceModel.availableVoices.map((VoiceModel v) => v.piperVoice).toSet();
    for (final NfScene scene in NfScene.all) {
      expect(voices, contains(scene.voice), reason: scene.id);
    }
  });
}
