import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_session_page.dart';
import 'package:vocabmaster/frontend_newest/theme/nf_theme_scope.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';

/// The daily review loop — the screen a learner opens more than any other, and
/// the one the transformation replaced wholesale. These pin the two things that
/// would quietly corrupt the scheduler if they drifted: that a grade cannot be
/// given before the meaning is revealed, and that Hard/Good/Easy still send the
/// SM-2 qualities the previous screen sent, under the source it sent them with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('NfSessionDeck', () {
    test('due words are the ones the scheduler raised for today', () {
      final List<Word> deck = <Word>[
        _word(1, 'due', reviewIn: const Duration(days: -1)),
        _word(2, 'today', reviewIn: Duration.zero),
        _word(3, 'later', reviewIn: const Duration(days: 3)),
        _word(4, 'unscheduled'),
      ];

      expect(
        NfSessionDeck.dueWords(deck).map((Word w) => w.englishWord),
        <String>['due', 'today'],
        reason: 'a word scheduled for a later day is not due',
      );
      expect(NfSessionDeck.dueCount(deck), 2);
      expect(NfSessionDeck.canStart(deck), isTrue);
    });

    test('an empty deck cannot start a session', () {
      expect(NfSessionDeck.canStart(<Word>[]), isFalse);
      expect(NfSessionDeck.dueCount(<Word>[]), 0);
    });

    test('with nothing due it falls back to a capped batch, not the whole deck',
        () {
      // The legacy screen fell back to every saved word, which turns "a quick
      // session" into an open-ended slog. The cap also has to match the Today
      // page's review target, or the plan and the session it opens disagree
      // about how many cards there are.
      final List<Word> deck = <Word>[
        for (int i = 0; i < 40; i++) _word(i + 1, 'w$i'),
      ];
      expect(NfSessionDeck.dueWords(deck), isEmpty);
      expect(NfSessionDeck.select(deck).length, 10);
    });

    test('due words are preferred over unscheduled ones', () {
      final List<Word> deck = <Word>[
        _word(1, 'unscheduled-a'),
        _word(2, 'due', reviewIn: const Duration(days: -2)),
        _word(3, 'unscheduled-b'),
      ];
      expect(NfSessionDeck.select(deck).map((Word w) => w.englishWord),
          <String>['due']);
    });
  });

  testWidgets('a grade cannot be given before the meaning is revealed',
      (WidgetTester tester) async {
    // Grading a card the learner never tried to recall records a memory
    // observation that never happened. The buttons are on screen from the start
    // so the session is legible, but they do nothing until the reveal.
    final _RecordingAppState appState = _RecordingAppState(<Word>[
      _word(1, 'insight', reviewIn: const Duration(days: -1)),
    ]);

    await _pumpSession(tester, appState);

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(appState.submitted, isEmpty,
        reason: 'a grade was recorded before the meaning was shown');

    await tester.tap(find.text('Tap to reveal the meaning'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(appState.submitted.single.quality, 4);
  });

  testWidgets('Hard, Good and Easy send the SM-2 qualities the scheduler reads',
      (WidgetTester tester) async {
    final _RecordingAppState appState = _RecordingAppState(<Word>[
      _word(1, 'alpha', reviewIn: const Duration(days: -1)),
      _word(2, 'beta', reviewIn: const Duration(days: -1)),
      _word(3, 'gamma', reviewIn: const Duration(days: -1)),
    ]);

    await _pumpSession(tester, appState);

    for (final String label in <String>['Hard', 'Good', 'Easy']) {
      await tester.tap(find.text('Tap to reveal the meaning'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(appState.submitted.map((_Review r) => r.quality), <int>[2, 4, 5]);
    expect(
      appState.submitted.map((_Review r) => r.source).toSet(),
      <String>{'classic_review'},
      reason: 'the redesign must not split review history under a new label',
    );
  });

  testWidgets('finishing the deck hands over to the summary, not a spent card',
      (WidgetTester tester) async {
    final _RecordingAppState appState = _RecordingAppState(<Word>[
      _word(1, 'solitary', reviewIn: const Duration(days: -1)),
    ]);

    await _pumpSession(tester, appState);
    await tester.tap(find.text('Tap to reveal the meaning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();

    expect(find.text('1 Easy'), findsOneWidget,
        reason: 'the session did not hand over to its summary');
    expect(find.text('Tap to reveal the meaning'), findsNothing);
  });
  testWidgets('a fill-in-the-blank card hides the word and the button that says it',
      (WidgetTester tester) async {
    // The second card is the cloze one: cards alternate so a session keeps both
    // directions of recall. What matters here is that neither the word nor the
    // pronounce button is on screen — a button that reads the answer aloud is
    // not a hint, it is the answer, and the card would look perfectly fine
    // while giving itself away.
    final _RecordingAppState appState = _RecordingAppState(<Word>[
      _word(1, 'first', reviewIn: const Duration(days: -2)),
      _word(2, 'underneath',
          reviewIn: const Duration(days: -1),
          sentence: 'They lived underneath a fir-tree.'),
    ]);

    await _pumpSession(tester, appState);

    // Grade past the first card to reach the cloze one.
    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.textContaining('_____'), findsOneWidget);
    expect(find.text('underneath'), findsNothing);
    expect(find.byIcon(LucideIcons.volume2), findsNothing);
  });

  testWidgets('revealing a fill-in-the-blank card gives up the word',
      (WidgetTester tester) async {
    final _RecordingAppState appState = _RecordingAppState(<Word>[
      _word(1, 'first', reviewIn: const Duration(days: -2)),
      _word(2, 'underneath',
          reviewIn: const Duration(days: -1),
          sentence: 'They lived underneath a fir-tree.'),
    ]);

    await _pumpSession(tester, appState);
    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pumpAndSettle();

    // The answer arrives in the gap it was asked for, in the same line and the
    // same place. Swapping the sentence for the bare word put it somewhere the
    // reader was not looking, and the card read as though it had moved on.
    expect(find.textContaining('_____'), findsNothing);
    // findRichText, because the filled line marks the answer inside it and is
    // therefore spans rather than a plain Text.
    expect(
        find.textContaining('They lived underneath a fir-tree.',
            findRichText: true),
        findsOneWidget);
    expect(find.byIcon(LucideIcons.volume2), findsOneWidget);

    // And the sentence is not printed twice: the answer block's example box
    // would be saying the same line again, right underneath it.
    expect(find.textContaining('"They lived underneath a fir-tree."'),
        findsNothing);
  });

  testWidgets('a word with no usable sentence is still asked the plain way',
      (WidgetTester tester) async {
    // Most of a deck built before the reader existed has no sentence at all,
    // and hand-added words often carry an example that does not contain them.
    // Those cards must not turn into a blank with nothing taken out.
    final _RecordingAppState appState = _RecordingAppState(<Word>[
      _word(1, 'first', reviewIn: const Duration(days: -2)),
      _word(2, 'absent',
          reviewIn: const Duration(days: -1),
          sentence: 'This example never uses the saved word.'),
    ]);

    await _pumpSession(tester, appState);
    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();

    expect(find.textContaining('_____'), findsNothing);
    expect(find.text('absent'), findsOneWidget);
  });

}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pumpSession(
  WidgetTester tester,
  AppStateProvider appState,
) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
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
        home: const NfThemeScope(child: NfSessionPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Word _word(int id, String english, {Duration? reviewIn, String? sentence}) => Word(
      id: id,
      englishWord: english,
      turkishMeaning: '$english-tr',
      learnedDate: DateTime(2026, 1, 1),
      difficulty: 'medium',
      nextReviewDate: reviewIn == null ? null : DateTime.now().add(reviewIn),
      sentences: sentence == null
          ? const <Sentence>[]
          : <Sentence>[
              Sentence(
                id: id * 100,
                sentence: sentence,
                translation: '',
                wordId: id,
                difficulty: 'medium',
              ),
            ],
    );

class _Review {
  const _Review(this.wordId, this.quality, this.source);
  final int wordId;
  final int quality;
  final String source;
}

class _RecordingAppState extends AppStateProvider {
  _RecordingAppState(this._words);

  final List<Word> _words;
  final List<_Review> submitted = <_Review>[];

  @override
  List<Word> get allWords => _words;

  @override
  Map<String, dynamic> get userStats => <String, dynamic>{'streak': 3};

  @override
  Future<Word?> submitWordReview({
    required int wordId,
    required int quality,
    String? source,
    int? responseMs,
  }) async {
    submitted.add(_Review(wordId, quality, source ?? ''));
    return null;
  }
}
