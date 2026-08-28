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

  Word word({int reviewCount = 0, DateTime? last, DateTime? next}) => Word(
        id: (next?.millisecondsSinceEpoch ?? 0) + reviewCount,
        englishWord: 'flight${next?.day ?? 0}$reviewCount',
        turkishMeaning: 'uçuş',
        learnedDate: DateTime(2026, 1, 1),
        difficulty: 'easy',
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

  Future<void> showWords(WidgetTester tester, List<Word> words) async {
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
          home: const Scaffold(body: NfWordsPage()),
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
}
