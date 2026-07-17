import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/screens/repeat_page.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

class _FakeApiService extends ApiService {
  _FakeApiService(this.words);

  final List<Word> words;

  @override
  Future<List<Word>> getAllWords() async => words;
}

class _FakeAppStateProvider extends AppStateProvider {
  int submitCalls = 0;
  int? lastWordId;
  int? lastQuality;
  bool throwOnSubmit = false;

  @override
  Future<Word?> submitWordReview({
    required int wordId,
    required int quality,
  }) async {
    submitCalls++;
    lastWordId = wordId;
    lastQuality = quality;
    if (throwOnSubmit) {
      throw Exception('offline');
    }
    return null;
  }
}

Word _word(int id, String english) => Word(
      id: id,
      englishWord: english,
      turkishMeaning: 'anlam-$id',
      learnedDate: DateTime(2026, 7, 1),
      difficulty: 'easy',
    );

Future<void> _pumpRepeatPage(
  WidgetTester tester,
  _FakeAppStateProvider appState,
  List<Word> words,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        home: RepeatPage(apiService: _FakeApiService(words)),
      ),
    ),
  );
  // RepeatPage runs looping background animations; bounded pumps only.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // flutter_tts has no test implementation; stub its channel so
    // RepeatPage._initTts does not throw MissingPluginException.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  testWidgets('grade buttons submit SM-2 quality and advance the card',
      (tester) async {
    final appState = _FakeAppStateProvider();
    await _pumpRepeatPage(
      tester,
      appState,
      [_word(11, 'resilient'), _word(12, 'insight')],
    );

    expect(find.text('resilient'), findsOneWidget);
    expect(find.byKey(const ValueKey('srs-grade-good')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('srs-grade-good')));
    await tester.tap(find.byKey(const ValueKey('srs-grade-good')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(appState.submitCalls, 1);
    expect(appState.lastWordId, 11);
    expect(appState.lastQuality, 4);
    // Advanced to the next card.
    expect(find.text('insight'), findsOneWidget);
  });

  testWidgets('hard and easy grades map to SM-2 qualities 2 and 5',
      (tester) async {
    final appState = _FakeAppStateProvider();
    await _pumpRepeatPage(
      tester,
      appState,
      [_word(21, 'delay'), _word(22, 'focus')],
    );

    await tester.tap(
      find.byKey(const ValueKey('srs-grade-hard')).first,
      warnIfMissed: false,
    );
    // Let the 400ms AnimatedSwitcher card transition fully finish so the
    // outgoing card (and its duplicate-keyed buttons) leaves the tree.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(appState.lastQuality, 2);
    expect(appState.lastWordId, 21);

    await tester.tap(
      find.byKey(const ValueKey('srs-grade-easy')).first,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(appState.lastQuality, 5);
    expect(appState.lastWordId, 22);
    expect(appState.submitCalls, 2);
  });

  testWidgets('submit failure (offline) still advances without crashing',
      (tester) async {
    final appState = _FakeAppStateProvider()..throwOnSubmit = true;
    await _pumpRepeatPage(
      tester,
      appState,
      [_word(31, 'alpha'), _word(32, 'beta')],
    );

    await tester.ensureVisible(find.byKey(const ValueKey('srs-grade-good')));
    await tester.tap(find.byKey(const ValueKey('srs-grade-good')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(appState.submitCalls, 1);
    expect(find.text('beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
