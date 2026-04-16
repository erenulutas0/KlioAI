import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import '../bloc/neural_game_bloc.dart';
import '../bloc/neural_game_event.dart';
import '../bloc/neural_game_state.dart';
import '../models/neural_game_mode.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/neural/neural_center_node.dart';
import '../widgets/neural/neural_combo_meter.dart';
import '../widgets/neural/neural_connection_lines.dart';
import '../widgets/neural/neural_input_box.dart';
import '../widgets/neural/neural_particle_background.dart';
import '../widgets/neural/neural_score_card.dart';
import '../widgets/neural/neural_word_node.dart';

class NeuralGamePlayScreen extends StatefulWidget {
  final void Function(NeuralGameFinished result) onFinished;
  final VoidCallback onExit;
  final NeuralGameMode mode;

  const NeuralGamePlayScreen({
    super.key,
    required this.onFinished,
    required this.onExit,
    required this.mode,
  });

  @override
  State<NeuralGamePlayScreen> createState() => _NeuralGamePlayScreenState();
}

class _NeuralGamePlayScreenState extends State<NeuralGamePlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lineAnimationController;
  int _lastNodeCount = 0;

  @override
  void initState() {
    super.initState();
    _lineAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1,
    );
  }

  @override
  void dispose() {
    _lineAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(listen: true);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: selectedTheme.colors.backgroundGradient,
        ),
        child: BlocConsumer<NeuralGameBloc, NeuralGameState>(
          listener: (context, state) {
            if (state is NeuralGameFinished) {
              widget.onFinished(state);
              return;
            }

            if (state is NeuralGamePlaying &&
                state.discoveredNodes.length != _lastNodeCount) {
              _lastNodeCount = state.discoveredNodes.length;
              _lineAnimationController.forward(from: 0);
            }
          },
          builder: (context, state) {
            if (state is! NeuralGamePlaying) {
              return Center(
                child: CircularProgressIndicator(
                  color: selectedTheme.colors.accent,
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final playSize =
                    Size(constraints.maxWidth, constraints.maxHeight);
                final center = Offset(
                  constraints.maxWidth / 2,
                  constraints.maxHeight * 0.43,
                );
                final quickSuggestions = _buildQuickSuggestions(state);

                return Stack(
                  children: [
                    const NeuralParticleBackground(),
                    AnimatedBuilder(
                      animation: _lineAnimationController,
                      builder: (context, _) => NeuralConnectionLines(
                        centerPosition: center,
                        nodePositions: state.discoveredNodes
                            .map((node) => node.position)
                            .toList(),
                        animationValue: _lineAnimationController.value,
                      ),
                    ),
                    Positioned(
                      top: 44,
                      left: 16,
                      child: NeuralComboMeter(combo: max(1, state.combo)),
                    ),
                    Positioned(
                      top: 44,
                      right: 16,
                      child: NeuralScoreCard(score: state.score),
                    ),
                    Positioned(
                      top: 42,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: TextButton.icon(
                          onPressed: widget.onExit,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Menu'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            backgroundColor: selectedTheme.colors.background
                                .withOpacity(0.38),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: center.dx - 75,
                      top: center.dy - 75,
                      child: NeuralCenterNode(
                        word: state.currentWordSet.centerWord,
                        subtitle:
                            widget.mode == NeuralGameMode.turkishTranslation
                                ? 'Turkce karsiligini yaz'
                                : 'Related word mode',
                        timeLeft: state.timeLeft,
                        progress: state.timeLeft / 60,
                      ),
                    ),
                    ...state.discoveredNodes.asMap().entries.map(
                          (entry) => NeuralWordNode(
                            word: entry.value.word,
                            subtitle: entry.value.subtitle,
                            position: entry.value.position,
                            index: entry.key,
                          ),
                        ),
                    if (quickSuggestions.isNotEmpty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 92,
                        child: SizedBox(
                          height: 38,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: quickSuggestions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final suggestion = quickSuggestions[index];
                              return ActionChip(
                                label: Text(
                                  suggestion,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                backgroundColor: selectedTheme.colors.accent
                                    .withOpacity(0.20),
                                side: BorderSide(
                                  color: selectedTheme.colors.glassBorder,
                                  width: 1,
                                ),
                                onPressed: () {
                                  context.read<NeuralGameBloc>().add(
                                        SubmitWordEvent(
                                          word: suggestion,
                                          playAreaSize: playSize,
                                          centerPosition: center,
                                        ),
                                      );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 30,
                      child: NeuralInputBox(
                        shake: state.isError && state.feedbackMessage != null,
                        hintText:
                            widget.mode == NeuralGameMode.turkishTranslation
                                ? 'Turkce karsiligini yaz'
                                : 'Type a related word',
                        onSubmit: (word) {
                          context.read<NeuralGameBloc>().add(
                                SubmitWordEvent(
                                  word: word,
                                  playAreaSize: playSize,
                                  centerPosition: center,
                                ),
                              );
                        },
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 142,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: state.feedbackMessage == null
                            ? const SizedBox.shrink()
                            : Center(
                                child: Container(
                                  key: ValueKey<String>(state.feedbackMessage!),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: state.isError
                                        ? Colors.redAccent.withOpacity(0.18)
                                        : selectedTheme.colors.primary
                                            .withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: state.isError
                                          ? Colors.redAccent.withOpacity(0.45)
                                          : selectedTheme.colors.primary
                                              .withOpacity(0.45),
                                    ),
                                  ),
                                  child: Text(
                                    state.feedbackMessage!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  AppThemeConfig _currentTheme({bool listen = true}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  List<String> _buildQuickSuggestions(NeuralGamePlaying state) {
    final suggestions = <String>[];
    final used = state.usedWords.toSet();

    for (final relatedWord in state.currentWordSet.relatedWords) {
      final normalized = relatedWord.trim().toLowerCase();
      if (normalized.isEmpty || used.contains(normalized)) {
        continue;
      }

      if (state.mode == NeuralGameMode.turkishTranslation) {
        final translations =
            state.currentWordSet.turkishTranslations[relatedWord.toLowerCase()];
        if (translations != null && translations.isNotEmpty) {
          final first = translations.first.trim().toLowerCase();
          if (first.isNotEmpty && !suggestions.contains(first)) {
            suggestions.add(first);
          }
        }
      } else if (!suggestions.contains(normalized)) {
        suggestions.add(normalized);
      }
    }

    return suggestions.take(6).toList(growable: false);
  }
}
