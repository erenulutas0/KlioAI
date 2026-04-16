import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/neural_game_bloc.dart';
import '../bloc/neural_game_event.dart';
import '../bloc/neural_game_state.dart';
import '../models/neural_game_mode.dart';
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
    _bloc.add(StartGameEvent(mode: mode));
    setState(() => _view = _NeuralGameView.play);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _view == _NeuralGameView.menu,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _view != _NeuralGameView.menu) {
          _bloc.add(const ResetGameEvent());
          setState(() => _view = _NeuralGameView.menu);
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
                _bloc.add(const ResetGameEvent());
                setState(() => _view = _NeuralGameView.menu);
              },
              onFinished: (result) {
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
              _bloc.add(const ResetGameEvent());
              setState(() => _view = _NeuralGameView.menu);
            },
          ),
      },
    );
  }
}
