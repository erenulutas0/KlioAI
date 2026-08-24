import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_words_page.dart';
import 'package:vocabmaster/frontend_newest/theme/nf_theme_scope.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';

/// Adding a word is the whole loop of a vocabulary app, and the redesign made
/// it unreachable: the dictionary was offered only from the empty state here
/// and on Today, so the moment a learner saved their first word they could
/// never save a second. Nothing failed — there was simply no button anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<int> pumpWords(
    WidgetTester tester,
    List<Word> words, {
    Size size = const Size(420, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var opened = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AppStateProvider>.value(
            value: _StubAppState(words),
          ),
          ChangeNotifierProvider<NfFrontendPreference>(
            create: (_) => NfFrontendPreference(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // NfWordsPage is a tab body: in the app the shell supplies the
          // Scaffold, and its search field needs a Material ancestor.
          home: Scaffold(
            body: NfThemeScope(
              child: NfWordsPage(onOpenDictionary: () => opened++),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  Finder addControl() => find.bySemanticsLabel(
        RegExp('Kelime ekle|Add a word|Wort hinzufügen'),
      );

  testWidgets('a learner with words can still reach the dictionary',
      (WidgetTester tester) async {
    await pumpWords(tester, <Word>[
      Word(
        id: 1,
        englishWord: 'insight',
        turkishMeaning: 'içgörü',
        learnedDate: DateTime(2026, 1, 1),
        difficulty: 'easy',
      ),
    ]);

    expect(addControl(), findsOneWidget,
        reason: 'the Words tab offers no way to add a word');
  });

  testWidgets('the empty deck keeps its own way in', (WidgetTester tester) async {
    // Every size a phone actually is. The empty state is the first thing a new
    // learner sees, so it has to survive a short screen as well as a tall one.
    await pumpWords(tester, <Word>[], size: const Size(360, 640));
    await pumpWords(tester, <Word>[]);
    // The empty state's own button, which is what the header control was
    // standing in for before it existed. Matched across locales because the
    // test locale is not the shipping one.
    expect(
      find.textContaining(RegExp('Sözlüğü aç|Open dictionary|Wörterbuch öffnen')),
      findsOneWidget,
    );
  });

  testWidgets('tapping it opens the dictionary', (WidgetTester tester) async {
    var opened = 0;
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AppStateProvider>.value(
            value: _StubAppState(<Word>[
              Word(
                id: 1,
                englishWord: 'insight',
                turkishMeaning: 'içgörü',
                learnedDate: DateTime(2026, 1, 1),
                difficulty: 'easy',
              ),
            ]),
          ),
          ChangeNotifierProvider<NfFrontendPreference>(
            create: (_) => NfFrontendPreference(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // NfWordsPage is a tab body: in the app the shell supplies the
          // Scaffold, and its search field needs a Material ancestor.
          home: Scaffold(
            body: NfThemeScope(
              child: NfWordsPage(onOpenDictionary: () => opened++),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(addControl());
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}

class _StubAppState extends AppStateProvider {
  _StubAppState(this._words);

  final List<Word> _words;

  @override
  List<Word> get allWords => _words;

  @override
  bool get isLoadingWords => false;
}
