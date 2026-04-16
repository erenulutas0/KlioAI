import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocabmaster/models/neural_game_mode.dart';
import 'package:vocabmaster/bloc/neural_game_state.dart';
import 'package:vocabmaster/screens/neural_game_results_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NeuralGameFinished buildResult({
    required int finalScore,
    List<String> discoveredWords = const ['study', 'skill'],
  }) {
    return NeuralGameFinished(
      centerWord: 'LEARN',
      finalScore: finalScore,
      totalWords: discoveredWords.length,
      maxCombo: 3,
      discoveredWords: discoveredWords,
      mode: NeuralGameMode.relatedWords,
    );
  }

  testWidgets('shows existing best score when final score is not higher',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'neural_game_best_score': 900,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NeuralGameResultsScreen(
          result: buildResult(finalScore: 500),
          onPlayAgain: () {},
          onBackToMenu: () {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Best: 900'), findsOneWidget);
    expect(find.text('New best'), findsNothing);
  });

  testWidgets(
      'updates best score and shows new best when final score is higher',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'neural_game_best_score': 300,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NeuralGameResultsScreen(
          result: buildResult(finalScore: 700),
          onPlayAgain: () {},
          onBackToMenu: () {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('New best'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('neural_game_best_score'), 700);
  });
}
