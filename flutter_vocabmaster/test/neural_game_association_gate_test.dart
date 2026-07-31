import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/bloc/neural_game_bloc.dart';
import 'package:vocabmaster/bloc/neural_game_event.dart';
import 'package:vocabmaster/bloc/neural_game_state.dart';
import 'package:vocabmaster/models/neural_game_mode.dart';

/// The related-words mode used to accept anything that looked pronounceable.
///
/// Its fallback check asked only whether the input was three or more lowercase letters
/// containing a vowel with no tripled letter — so "blorp" passed, was scored as an "open
/// link" against TRAVEL, and the app told the learner that blorp is an English word
/// related to travel. Neither existence nor relatedness was ever tested, which meant the
/// one skill the mode claims to exercise was not being measured at all.

void main() {
  Future<NeuralGamePlaying> startGame(NeuralGameBloc bloc) async {
    bloc.add(const StartGameEvent(mode: NeuralGameMode.relatedWords));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final state = bloc.state;
    expect(state, isA<NeuralGamePlaying>());
    return state as NeuralGamePlaying;
  }

  Future<NeuralGamePlaying> submit(NeuralGameBloc bloc, String word) async {
    // The play area only decides where a node is drawn; it has no bearing on whether the
    // word is accepted, which is what these tests are about.
    bloc.add(SubmitWordEvent(
      word: word,
      playAreaSize: const Size(400, 700),
      centerPosition: const Offset(200, 350),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return bloc.state as NeuralGamePlaying;
  }

  test('invented words are rejected and score nothing', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    expect(started.score, 0);

    // Each of these clears every hurdle the old gate set: three or more letters, all
    // lowercase, at least one vowel, no letter three times in a row.
    for (final invented in ['blorp', 'grinth', 'quandel', 'zorbik', 'flimet']) {
      final after = await submit(bloc, invented);
      expect(after.score, 0,
          reason: '"$invented" is not a word and must not score against '
              '${started.currentWordSet.centerWord}');
      expect(after.discoveredNodes, isEmpty,
          reason: '"$invented" must not be added to the map');
    }
  });

  test('a real related word from the set is still accepted', () async {
    // The gate has to stay closed without closing the game: the curated associations must
    // continue to work.
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    final genuine = started.currentWordSet.relatedWords.first;

    final after = await submit(bloc, genuine);
    expect(after.score, greaterThan(0),
        reason: '"$genuine" is a curated association of '
            '${started.currentWordSet.centerWord}');
    expect(after.discoveredNodes, isNotEmpty);
  });

  test('an unrelated real word does not score either', () async {
    // "banana" is a real English word, which the old gate treated as sufficient. Being a
    // word was never the question — being related was.
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    final unrelated = started.currentWordSet.centerWord.toLowerCase() == 'health'
        ? 'asphalt'
        : 'banana';

    final after = await submit(bloc, unrelated);
    expect(after.score, 0,
        reason: '"$unrelated" is a word but not an association of '
            '${started.currentWordSet.centerWord}');
  });
}
