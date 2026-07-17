import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/neural_game_bloc.dart';
import '../bloc/neural_game_event.dart';
import '../bloc/neural_game_state.dart';
import '../models/neural_game_mode.dart';
import '../services/analytics_service.dart';
import 'neural_game_menu_screen.dart';
import 'neural_game_play_screen.dart';
import 'neural_game_results_screen.dart';

enum _NeuralGameView { menu, play, results }

class NeuralGamePage extends StatefulWidget {
  const NeuralGamePage({super.key});

  @override
  State<NeuralGamePage> createState() => _NeuralGamePageState();
}

class _NeuralGamePageState extends State<NeuralGamePage> {
  late final NeuralGameBloc _bloc;
  _NeuralGameView _view = _NeuralGameView.menu;
  NeuralGameFinished? _latestResult;
  NeuralGameMode _selectedMode = NeuralGameMode.relatedWords;

  @override
  void initState() {
    super.initState();
    _bloc = NeuralGameBloc();
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  void _startGame(NeuralGameMode mode) {
    _selectedMode = mode;
    unawaited(AnalyticsService.logNeuralGameStarted(mode: mode.name));
    _bloc.add(StartGameEvent(mode: mode));
    setState(() => _view = _NeuralGameView.play);
  }

  void _returnToMenu({required String source}) {
    unawaited(
      AnalyticsService.logNeuralGameExited(
        mode: _selectedMode.name,
        source: source,
      ),
    );
    _bloc.add(const ResetGameEvent());
    setState(() => _view = _NeuralGameView.menu);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _view == _NeuralGameView.menu,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _view != _NeuralGameView.menu) {
          _returnToMenu(source: 'system_back');
        }
      },
      child: switch (_view) {
        _NeuralGameView.menu => NeuralGameMenuScreen(
            onStart: _startGame,
            onBack: () => Navigator.pop(context),
          ),
        _NeuralGameView.play => BlocProvider.value(
            value: _bloc,
            child: NeuralGamePlayScreen(
              mode: _selectedMode,
              onExit: () {
                _returnToMenu(source: 'exit_button');
              },
              onFinished: (result) {
                unawaited(
                  AnalyticsService.logNeuralGameFinished(
                    mode: result.mode.name,
                    finalScore: result.finalScore,
                    totalWords: result.totalWords,
                    maxCombo: result.maxCombo,
                  ),
                );
                unawaited(
                  AnalyticsService.logPracticeCompleted(
                    type: 'neural_game',
                    score: result.finalScore,
                    totalQuestions: result.totalWords,
                  ),
                );
                setState(() {
                  _latestResult = result;
                  _view = _NeuralGameView.results;
                });
              },
            ),
          ),
        _NeuralGameView.results => NeuralGameResultsScreen(
            result: _latestResult!,
            onPlayAgain: () => _startGame(_selectedMode),
            onBackToMenu: () {
              _returnToMenu(source: 'results_back_to_menu');
            },
          ),
      },
    );
  }
}
