import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/frontend_newest/nf_frontend_preference.dart';
import 'package:vocabmaster/frontend_newest/screens/nf_word_detail_page.dart';
import 'package:vocabmaster/frontend_newest/theme/nf_theme_scope.dart';
import 'package:vocabmaster/l10n/app_localizations.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/models/word_meaning.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/services/api_service.dart';

/// The per-meaning sentence surface, which had no test when it shipped and two
/// defects that a test would have caught on the first run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// The page scrolls, and its list only builds what fits. On the default
  /// 800x600 surface the Unassigned section sits below the fold and is never
  /// built, so a finder for it reports "not found" whatever the code does.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'opening a word fetches it from the server, because meanings live only there',
    (WidgetTester tester) async {
      // The local database has no meanings column, so a word handed in from the
      // Words tab always arrives with an empty list. If the opening fetch does
      // not run, the entire per-meaning surface is invisible and the page shows
      // a false "showing what is saved on this device" notice.
      final _FakeApi api = _FakeApi(
        onGetWordById: (int id) async => _wordWithTwoMeanings(),
      );

      await _pump(tester, word: _localCopyWithoutMeanings(), api: api);

      expect(api.getWordByIdCalls, <int>[7],
          reason: 'the page never asked the server for the word');
      expect(find.textContaining('bank (river)'), findsOneWidget);
      expect(find.textContaining('bank (money)'), findsOneWidget);
    },
  );

  testWidgets(
    'assigning a sentence the server moved in place does not delete it',
    (WidgetTester tester) async {
      useTallSurface(tester);
      // POST /words/{id}/sentences is idempotent: given text that already
      // exists on the word it inserts nothing and instead gives the unassigned
      // row the meaning the caller now knows. The row that comes back IS the
      // row the learner tapped, so deleting it destroys their sentence - and
      // charges them the 5 XP a sentence deletion costs.
      final _FakeApi api = _FakeApi(
        onGetWordById: (int id) async => _wordWithTwoMeanings(),
        // What a real server returns: same sentence id, now carrying meaning 1.
        onAddSentence: (int? meaningId) async =>
            _wordWithTwoMeanings(unassignedSentenceMeaningId: meaningId),
      );
      final _RecordingAppState appState = _RecordingAppState();

      await _pump(tester,
          word: _localCopyWithoutMeanings(), api: api, appState: appState);

      await _tapAssignAndChooseFirstMeaning(tester);

      expect(api.addSentenceMeaningIds, <int?>[1],
          reason: 'the assign call did not reach the server');
      expect(
        appState.deletedSentenceIds,
        isEmpty,
        reason: 'the sentence the server had just assigned was deleted',
      );
    },
  );

  testWidgets(
    'assigning still clears a genuine duplicate the server did create',
    (WidgetTester tester) async {
      useTallSurface(tester);
      // The other branch: if the server really inserted a second row, the
      // original comes back still unassigned and is a duplicate to clear.
      final _FakeApi api = _FakeApi(
        onGetWordById: (int id) async => _wordWithTwoMeanings(),
        onAddSentence: (int? meaningId) async =>
            _wordWithTwoMeanings(unassignedSentenceMeaningId: null),
      );
      final _RecordingAppState appState = _RecordingAppState();

      await _pump(tester,
          word: _localCopyWithoutMeanings(), api: api, appState: appState);

      await _tapAssignAndChooseFirstMeaning(tester);

      expect(appState.deletedSentenceIds, <int>[900],
          reason: 'the leftover unassigned duplicate was not cleared');
    },
  );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester, {
  required Word word,
  required _FakeApi api,
  _RecordingAppState? appState,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppStateProvider>.value(
          value: appState ?? _RecordingAppState(),
        ),
        // NfThemeScope reads the learner's palette choice from this.
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
        home: NfThemeScope(
          child: NfWordDetailPage(word: word, apiService: api),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAssignAndChooseFirstMeaning(WidgetTester tester) async {
  final Finder assign = find.text('Assign to meaning');
  expect(assign, findsOneWidget,
      reason: 'the Unassigned section did not offer an assign control');
  await tester.tap(assign);
  await tester.pumpAndSettle();

  expect(find.text('Which meaning does this sentence show?'), findsOneWidget,
      reason: 'the meaning picker did not open');
  await tester.tap(find.text('bank (river)').last);
  await tester.pumpAndSettle();
}

/// What the Words tab hands over: the local row, with no meanings.
Word _localCopyWithoutMeanings() => Word(
      id: 7,
      englishWord: 'bank',
      turkishMeaning: 'kıyı, banka',
      learnedDate: DateTime(2026, 1, 1),
      difficulty: 'medium',
      sentences: <Sentence>[_unassignedSentence(null)],
    );

Sentence _unassignedSentence(int? meaningId) => Sentence(
      id: 900,
      sentence: 'We sat on the bank.',
      translation: 'Kıyıda oturduk.',
      wordId: 7,
      difficulty: 'easy',
      meaningId: meaningId,
    );

/// What the server returns.
Word _wordWithTwoMeanings({int? unassignedSentenceMeaningId}) => Word(
      id: 7,
      englishWord: 'bank',
      turkishMeaning: 'kıyı, banka',
      learnedDate: DateTime(2026, 1, 1),
      difficulty: 'medium',
      meanings: const <WordMeaning>[
        WordMeaning(id: 1, translation: 'bank (river)', position: 0),
        WordMeaning(id: 2, translation: 'bank (money)', position: 1),
      ],
      sentences: <Sentence>[_unassignedSentence(unassignedSentenceMeaningId)],
    );

class _FakeApi extends ApiService {
  _FakeApi({required this.onGetWordById, this.onAddSentence});

  final Future<Word> Function(int id) onGetWordById;
  final Future<Word> Function(int? meaningId)? onAddSentence;

  final List<int> getWordByIdCalls = <int>[];
  final List<int?> addSentenceMeaningIds = <int?>[];

  @override
  Future<Word> getWordById(int id) {
    getWordByIdCalls.add(id);
    return onGetWordById(id);
  }

  @override
  Future<Word> addSentenceToWord({
    required int wordId,
    required String sentence,
    String? translation,
    String? sourceTranslation,
    String? difficulty,
    int? meaningId,
  }) {
    addSentenceMeaningIds.add(meaningId);
    return onAddSentence!(meaningId);
  }
}

class _RecordingAppState extends AppStateProvider {
  final List<int> deletedSentenceIds = <int>[];

  @override
  Future<bool> deleteSentenceFromWord({
    required int wordId,
    required int sentenceId,
  }) async {
    deletedSentenceIds.add(sentenceId);
    return true;
  }
}
