import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../models/neural_game_mode.dart';

abstract class NeuralGameEvent extends Equatable {
  const NeuralGameEvent();

  @override
  List<Object?> get props => [];
}

class StartGameEvent extends NeuralGameEvent {
  final NeuralGameMode mode;

  const StartGameEvent({required this.mode});

  @override
  List<Object?> get props => [mode];
}

class SubmitWordEvent extends NeuralGameEvent {
  final String word;
  final Size playAreaSize;
  final Offset centerPosition;

  const SubmitWordEvent({
    required this.word,
    required this.playAreaSize,
    required this.centerPosition,
  });

  @override
  List<Object?> get props => [word, playAreaSize, centerPosition];
}

class TimerTickEvent extends NeuralGameEvent {
  const TimerTickEvent();
}

class DismissFeedbackEvent extends NeuralGameEvent {
  const DismissFeedbackEvent();
}

class ResetGameEvent extends NeuralGameEvent {
  const ResetGameEvent();
}
