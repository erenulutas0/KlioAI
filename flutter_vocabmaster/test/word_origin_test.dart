import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/word_origins.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/local_database_service.dart';

import 'test_helper.dart';

/// Where a saved word came from.
///
/// The server has only ever inferred this: daily words if the meaning text
/// carries a star, everything else "manual". So a word tapped out of a novel
/// has been filed identically to one typed into the dictionary box — and the
/// book is usually the reason the learner remembers saving it at all.
///
/// Three places have to agree for that to change, and each of them was a
/// separate way to lose the answer: the request has to carry it, the local
/// cache has to have somewhere to put it, and the row has to survive the sync
/// that overwrites it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the request carries it', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await AuthService().saveSession('t', 'r', <String, dynamic>{
        'id': 4,
        'userId': 4,
        'email': 'reader@test.local',
        'displayName': 'Reader',
        'userTag': '#00004',
        'role': 'USER',
      });
    });

    Future<Map<String, dynamic>> bodyOf(
        Future<void> Function(ApiService api) call) async {
      late Map<String, dynamic> sent;
      final ApiService api = ApiService(
        baseUrl: 'http://localhost:8080/api',
        client: MockClient((http.Request request) async {
          sent = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode(<String, Object?>{
              'id': 1,
              'englishWord': 'rabbit',
              'turkishMeaning': 'tavşan',
              'learnedDate': '2026-08-29',
              'difficulty': 'easy',
            }),
            201,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      await call(api);
      return sent;
    }

    test('a word saved from a book says so', () async {
      final Map<String, dynamic> body = await bodyOf((ApiService api) async {
        await api.createWord(
          english: 'rabbit',
          turkish: 'tavşan',
          addedDate: DateTime(2026, 8, 29),
          origin: WordOrigins.reader,
        );
      });

      expect(body['origin'], 'reader');
    });

    test('a caller with nothing to say sends nothing', () async {
      // The server fills it in from the meaning text when the key is absent,
      // and keeps whatever it is given. Sending an empty string instead of
      // omitting the key would overwrite that inference with nothing.
      final Map<String, dynamic> body = await bodyOf((ApiService api) async {
        await api.createWord(
          english: 'rabbit',
          turkish: 'tavşan',
          addedDate: DateTime(2026, 8, 29),
        );
      });

      expect(body.containsKey('origin'), isFalse);
    });
  });

  group('the cache keeps it', () {
    setUpAll(setupTestEnv);

    late LocalDatabaseService db;

    setUp(() async {
      await clearDatabase();
      db = LocalDatabaseService();
    });

    Word word(int id, {String? origin}) => Word(
          id: id,
          englishWord: 'rabbit$id',
          turkishMeaning: 'tavşan',
          learnedDate: DateTime(2026, 1, 1),
          difficulty: 'easy',
          origin: origin,
        );

    test('a word saved one at a time keeps its origin', () async {
      await db.saveWord(word(1, origin: WordOrigins.reader));

      expect((await db.getAllWords()).single.origin, 'reader');
    });

    test('and the bulk sync does not launder it off', () async {
      // The same insert, with the same ConflictAlgorithm.replace, that the
      // profile stamp was being lost through. Adding a column to one map and
      // not the other is exactly how that happened, so both are pinned.
      await db.saveWord(word(1, origin: WordOrigins.reader));
      await db.saveAllWords(<Word>[word(1, origin: WordOrigins.reader)]);

      expect((await db.getAllWords()).single.origin, 'reader');
    });

    test('a word from before this was recorded has no origin, not a wrong one',
        () async {
      // Every word on an upgrading install. They group as unlabelled rather
      // than being filed under whichever source sorts first.
      await db.saveAllWords(<Word>[word(1)]);

      expect((await db.getAllWords()).single.origin, isNull);
      expect(WordOrigins.labelKeyFor(null), isNull);
    });
  });

  group('the label', () {
    test('names each source it knows', () {
      expect(WordOrigins.labelKeyFor(WordOrigins.reader), 'words.origin.reader');
      expect(WordOrigins.labelKeyFor(WordOrigins.dailyWords),
          'words.origin.dailyWords');
      expect(WordOrigins.labelKeyFor(WordOrigins.manual), 'words.origin.manual');
    });

    test('and says nothing about one it does not', () {
      // A value this client has never heard of — a source added on the server
      // later — must read as absent rather than as one of these three.
      expect(WordOrigins.labelKeyFor('podcast'), isNull);
      expect(WordOrigins.labelKeyFor(''), isNull);
    });
  });
}
