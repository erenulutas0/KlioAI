import 'package:equatable/equatable.dart';

import '../models/neural_game_mode.dart';
import '../models/word_node.dart';
import '../models/word_set.dart';

abstract class NeuralGameState extends Equatable {
  const NeuralGameState();

  @override
  List<Object?> get props => [];
}

class NeuralGameInitial extends NeuralGameState {
  const NeuralGameInitial();
}

class NeuralGamePlaying extends NeuralGameState {
  static const Object _unset = Object();

  final WordSet currentWordSet;
  final List<NeuralWordNodeModel> discoveredNodes;
  final List<String> usedWords;
  final int score;
  final int combo;
  final int maxCombo;
  final int timeLeft;
  final NeuralGameMode mode;
  final String? feedbackMessage;
  final bool isError;

  const NeuralGamePlaying({
    required this.currentWordSet,
    required this.discoveredNodes,
    required this.usedWords,
    required this.score,
    required this.combo,
    required this.maxCombo,
    required this.timeLeft,
    required this.mode,
    this.feedbackMessage,
    this.isError = false,
  });

  @override
  List<Object?> get props => [
        currentWordSet,
        discoveredNodes,
        usedWords,
        score,
        combo,
        maxCombo,
        timeLeft,
        mode,
        feedbackMessage,
        isError,
      ];

  NeuralGamePlaying copyWith({
    WordSet? currentWordSet,
    List<NeuralWordNodeModel>? discoveredNodes,
    List<String>? usedWords,
    int? score,
    int? combo,
    int? maxCombo,
    int? timeLeft,
    NeuralGameMode? mode,
    Object? feedbackMessage = _unset,
    bool? isError,
  }) {
    return NeuralGamePlaying(
      currentWordSet: currentWordSet ?? this.currentWordSet,
      discoveredNodes: discoveredNodes ?? this.discoveredNodes,
      usedWords: usedWords ?? this.usedWords,
      score: score ?? this.score,
      combo: combo ?? this.combo,
      maxCombo: maxCombo ?? this.maxCombo,
      timeLeft: timeLeft ?? this.timeLeft,
      mode: mode ?? this.mode,
      feedbackMessage: identical(feedbackMessage, _unset)
          ? this.feedbackMessage
          : feedbackMessage as String?,
      isError: isError ?? this.isError,
    );
  }
}

class NeuralGameFinished extends NeuralGameState {
  final String centerWord;
  final int finalScore;
  final int totalWords;
  final int maxCombo;
  final List<String> discoveredWords;
  final NeuralGameMode mode;

  const NeuralGameFinished({
    required this.centerWord,
    required this.finalScore,
    required this.totalWords,
    required this.maxCombo,
    required this.discoveredWords,
    required this.mode,
  });

  @override
  List<Object?> get props => [
        centerWord,
        finalScore,
        totalWords,
        maxCombo,
        discoveredWords,
        mode,
      ];
}
