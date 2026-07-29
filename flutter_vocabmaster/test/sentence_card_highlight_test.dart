import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vocabmaster/models/sentence_view_model.dart';
import 'package:vocabmaster/models/word.dart';
import 'package:vocabmaster/screens/sentences_page.dart';
import 'package:vocabmaster/theme/theme_provider.dart';

/// The sentence card boxes the target word inside the sentence. It used to
/// locate it with a plain `indexOf` and then box exactly `word.length`
/// characters, so an inflected form lost its suffix out of the chip:
/// "He recovered quickly" rendered as "He [recover] ed quickly".

Word _word(String english) => Word(
      id: 1,
      englishWord: english,
      turkishMeaning: 'anlam',
      learnedDate: DateTime(2026, 7, 1),
      difficulty: 'medium',
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required String sentence,
  required String word,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: SentenceCard(
            difficultyLabel: 'MEDIUM',
            vm: SentenceViewModel(
              id: 1,
              sentence: sentence,
              translation: 'çeviri',
              difficulty: 'medium',
              word: _word(word),
              isPractice: false,
              date: DateTime(2026, 7, 29),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The chip is a WidgetSpan holding its own Text, so the highlighted token is
/// the only standalone Text carrying exactly the boxed characters.
void _expectHighlight(String expected) {
  expect(find.text(expected), findsOneWidget);
}

void main() {
  testWidgets('an inflected form is highlighted whole, suffix included',
      (tester) async {
    await _pumpCard(
      tester,
      sentence: 'He recovered quickly after a few days of rest.',
      word: 'recover',
    );

    _expectHighlight('recovered');
    // The stem must not be boxed on its own, which is what stranded the "ed".
    expect(find.text('recover'), findsNothing);
  });

  testWidgets('an exact match is highlighted unchanged', (tester) async {
    await _pumpCard(
      tester,
      sentence: 'We evaluate each answer before saving it.',
      word: 'evaluate',
    );

    _expectHighlight('evaluate');
  });

  testWidgets('other inflections stay inside the chip', (tester) async {
    await _pumpCard(
      tester,
      sentence: 'She elaborates on every point.',
      word: 'elaborate',
    );

    _expectHighlight('elaborates');
  });

  testWidgets('the stem is not boxed inside an unrelated word',
      (tester) async {
    await _pumpCard(
      tester,
      sentence: 'Concatenate the two lists.',
      word: 'cat',
    );

    // No highlight at all is correct here — better than boxing "cat" inside
    // "Concatenate".
    expect(find.text('cat'), findsNothing);
    expect(find.text('Concatenate'), findsNothing);
  });

  testWidgets('matching ignores case', (tester) async {
    await _pumpCard(
      tester,
      sentence: 'Recovered items go back on the shelf.',
      word: 'recover',
    );

    _expectHighlight('Recovered');
  });
}
