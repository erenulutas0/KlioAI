import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/screens/pronunciation_practice_page.dart';
import 'package:vocabmaster/services/pronunciation_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('problem word chips request single-word pronunciation playback',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final playedWords = <String>[];
    const targetText = 'The speaker gave a short example.';
    const report = PronunciationReport(
      targetText: targetText,
      transcript: 'The speaker gave example.',
      durationMs: 2600,
      accuracyScore: 67,
      paceScore: 100,
      overallScore: 75,
      missingWords: ['a', 'short'],
      extraWords: [],
      matchedWords: ['the', 'speaker', 'gave', 'example'],
      targetWordMarks: [
        PronunciationWordMark(
          word: 'the',
          status: PronunciationWordStatus.matched,
        ),
        PronunciationWordMark(
          word: 'speaker',
          status: PronunciationWordStatus.matched,
        ),
        PronunciationWordMark(
          word: 'gave',
          status: PronunciationWordStatus.matched,
        ),
        PronunciationWordMark(
          word: 'a',
          status: PronunciationWordStatus.missing,
        ),
        PronunciationWordMark(
          word: 'short',
          status: PronunciationWordStatus.missing,
        ),
        PronunciationWordMark(
          word: 'example',
          status: PronunciationWordStatus.matched,
        ),
      ],
      wordsPerMinute: 92,
      clarityLabel: 'Clear',
      summary: 'Good attempt. Focus on the highlighted missing words.',
      paceFeedback: 'Your pace is close to the natural range.',
      nextStep: 'Read once more and say a, short more clearly.',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: PronunciationPracticePage(
          initialText: targetText,
          initialReport: report,
          wordPronunciationPlayer: (word) async {
            playedWords.add(word);
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Word review'), findsOneWidget);
    expect(find.text('Missing or unclear'), findsOneWidget);
    expect(find.text('Tap a word to hear it.'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('pronunciation-feedback-word-short')),
    );
    await tester.tap(
      find.byKey(const ValueKey('pronunciation-feedback-word-short')),
    );
    await tester.pump();

    expect(playedWords, ['short']);
  });
}
