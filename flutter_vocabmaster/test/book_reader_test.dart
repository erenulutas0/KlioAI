import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_books_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/auth_service.dart';
import 'package:vocabmaster/services/learning_language_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';

/// The reading shelf, end to end from the wire to the screen.
///
/// The feature's whole design rests on one decision: a wrong translation
/// teaches worse than no translation, so most of the shelf ships untranslated
/// and the learning happens by tapping a word. That makes "absent translation
/// renders as absent" a correctness property, not a cosmetic one — a blank line
/// where a translation should be reads as a bug and invites a bug report about
/// working software.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    LocaleTextService.setAppLocale(const Locale('tr'));
    LearningLanguageService.setSourceLanguage('Turkish');
    await AuthService().saveSession('test_token', 'test_refresh', <String, dynamic>{
      'id': 4,
      'userId': 4,
      'email': 'reader@test.local',
      'displayName': 'Reader',
      'userTag': '#00004',
      'role': 'USER',
    });
  });

  const String base = 'http://localhost:8080/api';

  /// Serves one canned JSON body for whatever is asked.
  ApiService apiServing(Object body) => ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async => http.Response(
              json.encode(body),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
      );

  /// No NfThemeScope: NfTokens.of falls back to the platform brightness when
  /// there is no theme above it, so the pages paint without dragging the
  /// frontend-preference provider into a test about the shelf.
  Widget host(Widget child) => MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  group('shelf', () {
    testWidgets('lists books with their level and length', (WidgetTester tester) async {
      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          expect(request.url.path, '/api/books');
          return http.Response(
            json.encode(<Map<String, Object?>>[
              <String, Object?>{
                'slug': 'peter-rabbit',
                'title': 'The Tale of Peter Rabbit',
                'author': 'Beatrix Potter',
                'level': 'A1',
                'sentenceCount': 58,
                'lastSentenceIndex': 0,
                'started': false,
              },
            ]),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(host(NfBooksPage(apiService: api)));
      await tester.pumpAndSettle();

      expect(find.text('The Tale of Peter Rabbit'), findsOneWidget);
      expect(find.text('Beatrix Potter'), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
      expect(find.textContaining('58'), findsOneWidget);
    });

    testWidgets('an unopened book offers to start, not zero per cent',
        (WidgetTester tester) async {
      // A shelf that answered "0%" for every unopened book would read as "you
      // have read none of this" rather than "you have not begun", and the two
      // look identical to a reader who has just finished a chapter and
      // reopened the shelf.
      final ApiService listing = apiServing(<Map<String, Object?>>[
        <String, Object?>{
          'slug': 'heart-of-darkness',
          'title': 'Heart of Darkness',
          'author': 'Joseph Conrad',
          'level': 'C1',
          'sentenceCount': 2291,
          'lastSentenceIndex': 0,
          'started': false,
        },
      ]);

      await tester.pumpWidget(host(NfBooksPage(apiService: listing)));
      await tester.pumpAndSettle();

      expect(find.text('Başla'), findsOneWidget);
      expect(find.text('%0'), findsNothing);
    });
  });

  group('parsing', () {
    test('a sentence with no translation parses as null, not as an empty string',
        () async {
      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async => http.Response(
              json.encode(<String, Object?>{
                'slug': 'peter-rabbit',
                'title': 'The Tale of Peter Rabbit',
                'from': 0,
                'sentenceCount': 58,
                'sentences': <Map<String, Object?>>[
                  <String, Object?>{
                    'index': 0,
                    'chapterIndex': 0,
                    'chapterTitle': null,
                    'text': 'Once upon a time there were four little Rabbits.',
                    'translation': null,
                  },
                ],
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
      );

      final window = await api.getBookSentences(slug: 'peter-rabbit', from: 0);

      expect(window.sentences.single.translation, isNull);
      expect(window.sentences.single.hasTranslation, isFalse);
    });

    test('progress uses what the server kept, not what was asked for', () async {
      // The server only moves a bookmark forward. A client that trusted its own
      // number would show a reader as further back than they are, and write
      // that wrong number again on the next scroll.
      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async => http.Response(
              json.encode(<String, Object?>{
                'slug': 'peter-rabbit',
                'lastSentenceIndex': 40,
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
      );

      expect(
        await api.saveBookProgress(slug: 'peter-rabbit', sentenceIndex: 12),
        40,
      );
    });
  });
}
