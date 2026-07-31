import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/providers/app_state_provider.dart';
import 'package:vocabmaster/screens/repeat_page.dart';
import 'package:vocabmaster/services/api_service.dart';
import 'package:vocabmaster/services/locale_text_service.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

/// Regression cover for the Classic Review card.
///
/// The word, its meaning and the example box each used to live in their own
/// fixed `Expanded(flex:)` slot with a nested scroll view. A meaning that
/// wrapped to two lines was sliced mid-line, and tapping "tap to see the
/// translation" pushed the translation past the example box's own fold — the
/// divider appeared and the translation never did. They now share one scroll
/// area, so revealed content lands on screen.

class _FakeApiService extends ApiService {
  _FakeApiService(this.words);

  final List<Word> words;

  @override
  Future<List<Word>> getAllWords() async => words;
}

class _FakeAppStateProvider extends AppStateProvider {
  @override
  Future<Word?> submitWordReview({
    required int wordId,
    required int quality,
  }) async =>
      null;
}

const _longMeaning = 'ayrıntılı bir şekilde açıklamak, detaylandırmak';
const _example = 'She elaborated it well during the meeting.';
const _exampleTr = 'Toplantı sırasında konuyu ayrıntılı biçimde açıkladı.';

Word _wordWithSentence() => Word(
      id: 1,
      englishWord: 'elaborate',
      turkishMeaning: _longMeaning,
      learnedDate: DateTime(2026, 7, 1),
      difficulty: 'medium',
      sentences: [
        Sentence(
          id: 1,
          wordId: 1,
          sentence: _example,
          translation: _exampleTr,
        ),
      ],
    );

Future<void> _pumpCard(WidgetTester tester) async {
  // A real phone viewport — the bug only showed at heights where the flex
  // slots were tighter than their content.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>(
            create: (_) => _FakeAppStateProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        home: RepeatPage(apiService: _FakeApiService([_wordWithSentence()])),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
    // Pin the locale so the assertions below are not at the mercy of the host
    // machine's language.
    LocaleTextService.setAppLocale(const Locale('en'));
  });

  testWidgets('a wrapped meaning is laid out without being clipped',
      (tester) async {
    await _pumpCard(tester);

    // The meaning is hidden until the learner asks for it, so that grading measures
    // recall rather than reading speed. Reveal it before checking how it lays out.
    await tester.tap(find.byKey(const ValueKey('reveal-meaning')), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final meaning = find.text(_longMeaning);
    expect(meaning, findsOneWidget);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(meaning);
    // Every line of the meaning is inside the viewport, not sliced by the
    // bottom edge of a fixed flex slot.
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));
    expect(rect.height, greaterThan(0));
  });

  testWidgets('tapping the reveal actually shows the translation',
      (tester) async {
    await _pumpCard(tester);

    expect(find.text(_exampleTr), findsNothing);

    // English UI must not show Turkish copy — the screen was fully hardcoded
    // Turkish before.
    expect(find.text('Çeviri görmek için dokunun'), findsNothing);
    final reveal = find.text('Tap to see the translation');
    expect(reveal, findsOneWidget);
    await tester.ensureVisible(reveal);
    await tester.pump();
    await tester.tap(reveal);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final translation = find.text(_exampleTr);
    expect(translation, findsOneWidget);

    // The whole point of the bug: the text existed but sat outside the
    // visible box. Assert it is genuinely on screen.
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(translation);
    expect(rect.height, greaterThan(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));

    expect(tester.takeException(), isNull);
  });
}
