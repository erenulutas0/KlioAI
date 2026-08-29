import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_words_page.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/word_maturity.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';

/// The deck seen whole, rather than one row at a time.
///
/// The list has always answered "how well do I know this word" five dots at a
/// time. It has never answered the question a learner actually has, which is
/// how much of all this has stuck — and counting dots down a scrolling list is
/// not an answer.
///
/// The arithmetic is pinned in `word_maturity_test.dart`. What is checked here
/// is that the summary reports the deck and not the screen: the wrong list, or
/// a bar that follows a search, would be a confident number about the wrong
/// thing, and a summary is exactly the kind of number that gets believed.
class _LoadedAppState extends AppStateProvider {
  _LoadedAppState(this.words);

  final List<Word> words;

  @override
  bool get isInitialized => true;

  @override
  bool get isLoadingWords => false;

  @override
  List<Word> get allWords => words;

  @override
  Map<String, dynamic> get userStats => <String, dynamic>{'streak': 0, 'xp': 0};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Word word({
    int reviewCount = 0,
    DateTime? last,
    DateTime? next,
    String? english,
    String? origin,
  }) =>
      Word(
        id: (next?.millisecondsSinceEpoch ?? 0) + reviewCount,
        englishWord: english ?? 'flight${next?.day ?? 0}$reviewCount',
        turkishMeaning: 'uçuş',
        learnedDate: DateTime(2026, 1, 1),
        difficulty: 'easy',
        origin: origin,
        reviewCount: reviewCount,
        lastReviewDate: last,
        nextReviewDate: next,
      );

  /// A word the scheduler waits [days] on: one graded review, dated.
  Word waiting(int days) => word(
        reviewCount: 3,
        last: DateTime(2026, 3, 1),
        next: DateTime(2026, 3, 1).add(Duration(days: days)),
      );

  Future<void> showWords(
    WidgetTester tester,
    List<Word> words, {
    ValueChanged<List<Word>>? onReviewWords,
  }) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(
              value: _LoadedAppState(words)),
          ChangeNotifierProvider<NfFrontendPreference>(
              create: (_) => NfFrontendPreference()),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // NfWordsPage is a tab body, not a route: the shell supplies the
          // Scaffold it draws its text fields and ripples into.
          home: Scaffold(body: NfWordsPage(onReviewWords: onReviewWords)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the deck is summarised by stage', (WidgetTester tester) async {
    await showWords(tester, <Word>[
      word(),
      word(reviewCount: 0, next: DateTime(2026, 4, 1)),
      waiting(3),
      waiting(20),
      waiting(90),
    ]);

    expect(find.text('2 Bilinen'), findsOneWidget);
    expect(find.text('1 Öğrenilen'), findsOneWidget);
    expect(find.text('2 Yeni'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty deck shows no summary at all',
      (WidgetTester tester) async {
    // Three zeroes would be a bar reporting nothing, on the screen whose whole
    // job at that moment is to get the learner to add their first word.
    await showWords(tester, const <Word>[]);

    expect(find.textContaining('Bilinen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searching does not change what the summary reports',
      (WidgetTester tester) async {
    // The bar takes the whole deck, not the filtered list. One that moved while
    // someone typed would be reporting their search back at them as progress.
    await showWords(tester, <Word>[waiting(90), waiting(3), word()]);
    expect(find.text('1 Bilinen'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();

    expect(find.text('1 Bilinen'), findsOneWidget);
    expect(find.text('1 Öğrenilen'), findsOneWidget);
    expect(find.text('1 Yeni'), findsOneWidget);
  });
  group('a band starts a session over its own words', () {
    testWidgets('tapping one hands back exactly that band',
        (WidgetTester tester) async {
      // The point of the feature: "practise the ones I am still learning" is a
      // different request from "review what is due", and nothing new is ever
      // due — so the band a learner most wants would come back empty from the
      // other path.
      List<Word>? asked;
      await showWords(
        tester,
        <Word>[word(), waiting(3), waiting(20), waiting(90)],
        onReviewWords: (List<Word> w) => asked = w,
      );

      await tester.tap(find.text('2 Bilinen'));
      await tester.pump();

      expect(asked, isNotNull);
      expect(asked!.map(maturityFor).toSet(), <WordMaturity>{WordMaturity.known});
      expect(asked, hasLength(2));
    });

    testWidgets('an empty band is shown and does not open a session',
        (WidgetTester tester) async {
      // "0 Yeni" is true and worth reading. A session over nothing dead-ends on
      // a screen the shell is built never to reach.
      List<Word>? asked;
      await showWords(
        tester,
        <Word>[waiting(90)],
        onReviewWords: (List<Word> w) => asked = w,
      );

      expect(find.text('0 Yeni'), findsOneWidget);
      await tester.tap(find.text('0 Yeni'));
      await tester.pump();

      expect(asked, isNull);
    });

    testWidgets('with nowhere to send it, the bands stay a summary',
        (WidgetTester tester) async {
      await showWords(tester, <Word>[waiting(90)]);

      await tester.tap(find.text('1 Bilinen'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('the source filter', () {
    testWidgets('narrows the list to one group', (WidgetTester tester) async {
      await showWords(tester, <Word>[
        word(english: 'rabbit', origin: 'reader'),
        word(english: 'invoice', origin: 'manual'),
      ]);

      expect(find.text('rabbit'), findsOneWidget);
      expect(find.text('invoice'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('words-origin-reader')));
      await tester.pumpAndSettle();

      expect(find.text('rabbit'), findsOneWidget);
      expect(find.text('invoice'), findsNothing);
    });

    testWidgets('and gives the whole deck back', (WidgetTester tester) async {
      await showWords(tester, <Word>[
        word(english: 'rabbit', origin: 'reader'),
        word(english: 'invoice', origin: 'manual'),
      ]);

      await tester.tap(find.byKey(const ValueKey<String>('words-origin-reader')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('words-origin-all')));
      await tester.pumpAndSettle();

      expect(find.text('invoice'), findsOneWidget);
    });

    testWidgets('is not shown when there is nothing to choose between',
        (WidgetTester tester) async {
      // One source is not a choice, and a deck of words saved before
      // provenance existed has none at all.
      await showWords(tester, <Word>[
        word(english: 'rabbit', origin: 'reader'),
        word(english: 'invoice', origin: 'reader'),
      ]);

      expect(find.byKey(const ValueKey<String>('words-origin-all')), findsNothing);
    });

    testWidgets('the summary keeps reporting the whole deck',
        (WidgetTester tester) async {
      // Deliberate: the bar is a summary of what the learner has, not of what
      // the screen is showing. One that moved with the filter would report the
      // filter back at them as progress.
      await showWords(tester, <Word>[
        word(english: 'rabbit', origin: 'reader'),
        word(english: 'invoice', origin: 'manual'),
      ]);

      await tester.tap(find.byKey(const ValueKey<String>('words-origin-reader')));
      await tester.pumpAndSettle();

      expect(find.text('2 Yeni'), findsOneWidget);
    });
  });

}
