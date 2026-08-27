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
import 'package:vocabmaster/frontend_newest/screens/nf_reader_page.dart';
import 'package:vocabmaster/models/book.dart';
import 'package:vocabmaster/models/word.dart';
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

  group('saving a tapped word', () {
    testWidgets('the deck is told about the word, not just the server',
        (WidgetTester tester) async {
      // This is the failure the feature cannot afford, and it is silent: the
      // word reaches the server, the sheet says "added", and the Words screen
      // the learner opens next has never heard of it. On the device that read
      // exactly like a save that had failed -- the word was there the whole
      // time, one restart away.
      final List<Word> adopted = <Word>[];

      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/words')) {
            return http.Response(
              json.encode(<String, Object?>{
                'id': 77,
                'englishWord': 'underneath',
                'turkishMeaning': 'altında',
                'learnedDate': '2026-08-27',
              }),
              201,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200,
              headers: <String, String>{'content-type': 'application/json'});
        }),
      );

      await tester.pumpWidget(host(Scaffold(
        body: ReaderWordSheet(
          word: 'underneath',
          sentence: 'They lived underneath a fir-tree.',
          sentenceTranslation: null,
          api: api,
          onSaved: adopted.add,
          lookUp: (String w, String s) async => 'bir şeyin alt kısmında',
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Desteye ekle'));
      await tester.pumpAndSettle();

      expect(adopted, hasLength(1));
      expect(adopted.single.id, 77);
    });

    testWidgets('the line the word came from is kept even with no translation',
        (WidgetTester tester) async {
      // Five of the six books have no translation. If the sentence were only
      // attached when one existed, almost every word saved from the shelf would
      // land in the deck with no context -- and the context is most of what
      // makes reading worth learning from.
      //
      // An earlier version did exactly that, on the theory that an empty
      // translation would look like one that failed to load. It would not: the
      // review surface branches on hasTranslation and simply draws the sentence
      // alone. So the sentence goes, and the translation key is omitted rather
      // than sent empty.
      final List<String> paths = <String>[];
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          paths.add(request.url.path);
          if (request.body.isNotEmpty) {
            bodies.add(
                Map<String, dynamic>.from(json.decode(request.body) as Map));
          }
          return http.Response(
            json.encode(<String, Object?>{
              'id': 77,
              'englishWord': 'underneath',
              'turkishMeaning': 'altında',
              'learnedDate': '2026-08-27',
            }),
            201,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(host(Scaffold(
        body: ReaderWordSheet(
          word: 'underneath',
          sentence: 'They lived underneath a fir-tree.',
          sentenceTranslation: null,
          api: api,
          onSaved: (_) {},
          lookUp: (String w, String s) async => 'bir şeyin alt kısmında',
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Desteye ekle'));
      await tester.pumpAndSettle();

      expect(paths.where((p) => p.contains('/sentences')), hasLength(1));

      final Map<String, dynamic> sentenceBody =
          bodies.firstWhere((b) => b.containsKey('sentence'));
      expect(sentenceBody['sentence'], 'They lived underneath a fir-tree.');
      expect(sentenceBody.containsKey('translation'), isFalse);
    });

    testWidgets('a book that has a translation sends it with the sentence',
        (WidgetTester tester) async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          if (request.body.isNotEmpty) {
            bodies.add(
                Map<String, dynamic>.from(json.decode(request.body) as Map));
          }
          return http.Response(
            json.encode(<String, Object?>{
              'id': 78,
              'englishWord': 'underneath',
              'turkishMeaning': 'altında',
              'learnedDate': '2026-08-27',
            }),
            201,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(host(Scaffold(
        body: ReaderWordSheet(
          word: 'underneath',
          sentence: 'They lived underneath a fir-tree.',
          sentenceTranslation: 'Bir köknar ağacının altında yaşıyorlardı.',
          api: api,
          onSaved: (_) {},
          lookUp: (String w, String s) async => 'bir şeyin alt kısmında',
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Desteye ekle'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> sentenceBody =
          bodies.firstWhere((b) => b.containsKey('sentence'));
      expect(sentenceBody['translation'],
          'Bir köknar ağacının altında yaşıyorlardı.');
    });
  });

  group('finishing a book', () {
    test('the last sentence reads as finished, not as ninety-eight per cent', () {
      // lastSentenceIndex is a position, not a tally: a 58-sentence book has
      // indices 0..57, so dividing by 58 would leave someone who read every
      // word of it looking permanently almost-done.
      const BookShelfEntry finished = BookShelfEntry(
        slug: 'peter-rabbit',
        title: 'The Tale of Peter Rabbit',
        author: 'Beatrix Potter',
        level: 'A1',
        sentenceCount: 58,
        lastSentenceIndex: 57,
        started: true,
      );

      expect(finished.fraction, 1.0);
    });

    test('an unopened book is at zero, and a one-line book cannot divide by zero',
        () {
      const BookShelfEntry fresh = BookShelfEntry(
        slug: 'x', title: 'X', author: 'A', level: 'A1',
        sentenceCount: 58, lastSentenceIndex: 0, started: false,
      );
      const BookShelfEntry tiny = BookShelfEntry(
        slug: 'y', title: 'Y', author: 'A', level: 'A1',
        sentenceCount: 1, lastSentenceIndex: 0, started: true,
      );

      expect(fresh.fraction, 0);
      expect(tiny.fraction, 0);
    });

    testWidgets('a finished book opens at its first page, not its last line',
        (WidgetTester tester) async {
      // Opening at the bookmark showed one sentence and a screenful of nothing,
      // with no way to scroll back — a strange way to be told "you have read
      // this".
      final List<String> queries = <String>[];

      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          queries.add(request.url.query);
          return http.Response(
            json.encode(<String, Object?>{
              'slug': 'peter-rabbit',
              'title': 'The Tale of Peter Rabbit',
              'from': 0,
              'sentenceCount': 58,
              'sentences': <Map<String, Object?>>[],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(host(NfReaderPage(
        slug: 'peter-rabbit',
        title: 'The Tale of Peter Rabbit',
        startAt: 57,
        sentenceCount: 58,
        apiService: api,
      )));
      await tester.pumpAndSettle();

      expect(queries.single, contains('from=0'));
    });

    testWidgets('an unfinished book still opens where it was left',
        (WidgetTester tester) async {
      final List<String> queries = <String>[];

      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          queries.add(request.url.query);
          return http.Response(
            json.encode(<String, Object?>{
              'slug': 'peter-rabbit',
              'title': 'The Tale of Peter Rabbit',
              'from': 30,
              'sentenceCount': 58,
              'sentences': <Map<String, Object?>>[],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(host(NfReaderPage(
        slug: 'peter-rabbit',
        title: 'The Tale of Peter Rabbit',
        startAt: 30,
        sentenceCount: 58,
        apiService: api,
      )));
      await tester.pumpAndSettle();

      expect(queries.single, contains('from=30'));
    });
  });

  group('listening', () {
    /// A window holding one ordinary sentence and one too long to synthesise.
    Map<String, Object?> windowWithLongSentence() => <String, Object?>{
          'slug': 'jekyll-and-hyde',
          'title': 'The Strange Case of Dr Jekyll and Mr Hyde',
          'from': 0,
          'sentenceCount': 2,
          'sentences': <Map<String, Object?>>[
            <String, Object?>{
              'index': 0,
              'chapterIndex': 0,
              'chapterTitle': null,
              'text': 'Mr. Utterson the lawyer was a man of a rugged countenance.',
              'translation': null,
            },
            <String, Object?>{
              'index': 1,
              'chapterIndex': 0,
              'chapterTitle': null,
              // 39 of the shelf's 13,441 sentences are past the server's limit;
              // the longest is 678 characters.
              'text': 'A very long sentence. ' * 40,
              'translation': null,
            },
          ],
        };

    testWidgets('a sentence too long to speak gets no speaker at all',
        (WidgetTester tester) async {
      // The alternative is a control that answers with an error. A reader who
      // taps it learns nothing except that the app is broken, which it is not:
      // the limit is the server refusing to fork a synthesis job of unbounded
      // size on a shared machine.
      await tester.pumpWidget(host(NfReaderPage(
        slug: 'jekyll-and-hyde',
        title: 'Jekyll',
        apiService: apiServing(windowWithLongSentence()),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });
  });

  group('a word already in the deck', () {
    testWidgets('is reported as already there, and cannot be added twice',
        (WidgetTester tester) async {
      // Prose repeats itself: meeting the same word twice in one book is the
      // normal case. Nothing on the server refuses a second copy, so without
      // this the deck fills with duplicates of whatever the book says often --
      // and each duplicate is reviewed as its own card.
      final List<String> posted = <String>[];

      final ApiService api = ApiService(
        baseUrl: base,
        client: MockClient((http.Request request) async {
          posted.add(request.url.path);
          return http.Response('{}', 200,
              headers: <String, String>{'content-type': 'application/json'});
        }),
      );

      await tester.pumpWidget(host(Scaffold(
        body: ReaderWordSheet(
          word: 'underneath',
          sentence: 'They lived underneath a fir-tree.',
          sentenceTranslation: null,
          api: api,
          onSaved: (_) {},
          alreadySaved: true,
          lookUp: (String w, String s) async => 'bir şeyin alt kısmında',
        ),
      )));
      await tester.pumpAndSettle();

      // "Already there" and "just added" are different news and read
      // differently.
      expect(find.text('Zaten destende'), findsOneWidget);
      expect(find.text('Desteye ekle'), findsNothing);

      await tester.tap(find.text('Zaten destende'));
      await tester.pumpAndSettle();

      expect(posted.where((String p) => p.endsWith('/words')), isEmpty);
    });
  });

  group('running out of AI quota while reading', () {
    testWidgets('says the daily limit is reached, not that something broke',
        (WidgetTester tester) async {
      // Reading is the flow that exhausts the quota: an unknown word every few
      // lines, and a tap on each one. "Could not get the meaning" tells the
      // learner the app is broken when it is doing exactly what it was told,
      // and gives them nothing to act on.
      await tester.pumpWidget(host(Scaffold(
        body: ReaderWordSheet(
          word: 'underneath',
          sentence: 'They lived underneath a fir-tree.',
          sentenceTranslation: null,
          api: apiServing(<String, Object?>{}),
          onSaved: (_) {},
          // The reason the server actually sends when the daily allowance is
          // gone. Without it the formatter falls back to the raw message and
          // the test would be checking nothing about quotas.
          lookUp: (String w, String s) async => throw ApiQuotaExceededException(
              message: 'quota', reason: 'daily-token-quota'),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Günlük AI hakkın doldu'), findsOneWidget);
      expect(find.text('Anlam alınamadı.'), findsNothing);
    });
  });
}
