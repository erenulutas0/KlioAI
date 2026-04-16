import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/bloc/neural_game_bloc.dart';
import 'package:vocabmaster/bloc/neural_game_event.dart';
import 'package:vocabmaster/bloc/neural_game_state.dart';
import 'package:vocabmaster/models/neural_game_mode.dart';

void main() {
  const playAreaSize = Size(390, 844);
  const centerPosition = Offset(195, 360);

  Future<NeuralGamePlaying> startGame(
    NeuralGameBloc bloc, {
    NeuralGameMode mode = NeuralGameMode.relatedWords,
  }) async {
    bloc.add(StartGameEvent(mode: mode));
    final state = await bloc.stream.firstWhere((s) => s is NeuralGamePlaying);
    return state as NeuralGamePlaying;
  }

  test('StartGameEvent initializes playing state with defaults', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final state = await startGame(bloc);

    expect(state.timeLeft, 60);
    expect(state.score, 0);
    expect(state.combo, 0);
    expect(state.maxCombo, 0);
    expect(state.usedWords, isEmpty);
    expect(state.discoveredNodes, isEmpty);
  });

  test('valid word increases score, combo, and discovered nodes', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    final validWord = started.currentWordSet.relatedWords.first;

    bloc.add(
      SubmitWordEvent(
        word: validWord.toUpperCase(),
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );

    final state = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying &&
          s.usedWords.contains(validWord.toLowerCase()) &&
          s.discoveredNodes.isNotEmpty;
    }) as NeuralGamePlaying;

    expect(state.score, 100);
    expect(state.combo, 1);
    expect(state.maxCombo, 1);
    expect(state.discoveredNodes.length, 1);
    expect(state.isError, isFalse);
    expect(state.feedbackMessage, contains('+100'));
  });

  test('input phrase accepts embedded related word token', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    final validWord = started.currentWordSet.relatedWords.first;

    bloc.add(
      SubmitWordEvent(
        word: 'my ${validWord.toUpperCase()} idea',
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );

    final state = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying &&
          s.usedWords.contains(validWord.toLowerCase()) &&
          s.discoveredNodes.isNotEmpty;
    }) as NeuralGamePlaying;

    expect(state.score, 100);
    expect(state.combo, 1);
    expect(state.isError, isFalse);
  });

  test('related mode accepts loose association words', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    await startGame(bloc);

    bloc.add(
      const SubmitWordEvent(
        word: 'plane abroad',
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );

    final state = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying &&
          s.usedWords.any((w) => w.startsWith('soft:')) &&
          s.discoveredNodes.isNotEmpty;
    }) as NeuralGamePlaying;

    expect(state.score, 70);
    expect(state.combo, 1);
    expect(state.isError, isFalse);
  });

  test('duplicate word returns error and does not change score', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    final validWord = started.currentWordSet.relatedWords.first;

    bloc.add(
      SubmitWordEvent(
        word: validWord,
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );
    final acceptedState = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying && s.usedWords.length == 1;
    }) as NeuralGamePlaying;

    bloc.add(
      SubmitWordEvent(
        word: '  ${validWord.toUpperCase()}  ',
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );
    final duplicateState = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying &&
          s.isError &&
          s.feedbackMessage == 'Already used';
    }) as NeuralGamePlaying;

    expect(duplicateState.score, acceptedState.score);
    expect(duplicateState.combo, acceptedState.combo);
    expect(duplicateState.maxCombo, acceptedState.maxCombo);
    expect(duplicateState.usedWords.length, acceptedState.usedWords.length);
  });

  test('invalid word decreases combo by one and preserves maxCombo', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);
    final words = started.currentWordSet.relatedWords.take(2).toList();

    bloc.add(
      SubmitWordEvent(
        word: words[0],
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );
    await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying && s.combo == 1;
    });

    bloc.add(
      SubmitWordEvent(
        word: words[1],
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );
    final comboTwoState = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying && s.combo == 2;
    }) as NeuralGamePlaying;

    bloc.add(
      const SubmitWordEvent(
        word: 'zzzqqq',
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );
    final invalidState = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying &&
          s.isError &&
          (s.feedbackMessage?.contains('Close one') ?? false);
    }) as NeuralGamePlaying;

    expect(comboTwoState.score, 220);
    expect(invalidState.combo, 1);
    expect(invalidState.maxCombo, 2);
    expect(invalidState.score, comboTwoState.score);
  });

  test('timer ticks move game to finished state at zero', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(bloc);

    for (var i = 0; i < 59; i++) {
      bloc.add(const TimerTickEvent());
    }
    final oneSecondLeftState = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying && s.timeLeft == 1;
    }) as NeuralGamePlaying;

    bloc.add(const TimerTickEvent());
    final finishedState = await bloc.stream
        .firstWhere((s) => s is NeuralGameFinished) as NeuralGameFinished;

    expect(oneSecondLeftState.timeLeft, 1);
    expect(finishedState.centerWord, started.currentWordSet.centerWord);
    expect(finishedState.finalScore, oneSecondLeftState.score);
    expect(finishedState.totalWords, oneSecondLeftState.discoveredNodes.length);
    expect(finishedState.maxCombo, oneSecondLeftState.maxCombo);
  });

  test('turkish translation mode accepts mapped translation', () async {
    final bloc = NeuralGameBloc();
    addTearDown(bloc.close);

    final started = await startGame(
      bloc,
      mode: NeuralGameMode.turkishTranslation,
    );
    final targetWord = started.currentWordSet.relatedWords.first.toLowerCase();
    final translationOptions =
        started.currentWordSet.turkishTranslations[targetWord] ?? const [];
    final answer = translationOptions.first;

    bloc.add(
      SubmitWordEvent(
        word: answer,
        playAreaSize: playAreaSize,
        centerPosition: centerPosition,
      ),
    );

    final accepted = await bloc.stream.firstWhere((s) {
      return s is NeuralGamePlaying && s.usedWords.contains(targetWord);
    }) as NeuralGamePlaying;

    expect(accepted.mode, NeuralGameMode.turkishTranslation);
    expect(accepted.discoveredNodes.first.subtitle, isNotEmpty);
    expect(accepted.isError, isFalse);
  });
}
