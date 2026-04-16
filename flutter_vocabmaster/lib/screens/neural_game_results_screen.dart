import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bloc/neural_game_state.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/neural/glassmorphism_card.dart';
import '../widgets/neural/neural_particle_background.dart';

class NeuralGameResultsScreen extends StatefulWidget {
  final NeuralGameFinished result;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToMenu;

  const NeuralGameResultsScreen({
    super.key,
    required this.result,
    required this.onPlayAgain,
    required this.onBackToMenu,
  });

  @override
  State<NeuralGameResultsScreen> createState() =>
      _NeuralGameResultsScreenState();
}

class _NeuralGameResultsScreenState extends State<NeuralGameResultsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  int _bestScore = 0;
  bool _isNewBest = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _loadBestScore();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    final currentBest = prefs.getInt('neural_game_best_score') ?? 0;

    if (widget.result.finalScore > currentBest) {
      await prefs.setInt('neural_game_best_score', widget.result.finalScore);
      if (!mounted) {
        return;
      }
      setState(() {
        _bestScore = widget.result.finalScore;
        _isNewBest = true;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _bestScore = currentBest);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme();
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: selectedTheme.colors.backgroundGradient,
        ),
        child: Stack(
          children: [
            const NeuralParticleBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: GlassmorphismCard(
                      child: Column(
                        children: [
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1.10)
                                .animate(_pulseController),
                            child: Container(
                              width: 86,
                              height: 86,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: selectedTheme.colors.buttonGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: selectedTheme.colors.accentGlow
                                        .withOpacity(0.35),
                                    blurRadius: 20,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.emoji_events_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Run Complete',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Center word: ${widget.result.centerWord}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.result.mode.name == 'turkishTranslation'
                                ? 'Mode: Turkce Karsilik'
                                : 'Mode: Iliskili Kelime',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.62),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildStatsGrid(selectedTheme),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withOpacity(0.03),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Discovered Words',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: widget.result.discoveredWords
                                      .map(
                                        (word) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            color: selectedTheme.colors.primary
                                                .withOpacity(0.15),
                                            border: Border.all(
                                              color: selectedTheme.colors.accent
                                                  .withOpacity(0.32),
                                            ),
                                          ),
                                          child: Text(
                                            word,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: widget.onPlayAgain,
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('Tekrar Oyna'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedTheme.colors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: widget.onBackToMenu,
                            icon: const Icon(Icons.grid_view_rounded),
                            label: const Text('Menuye Don'),
                            style: TextButton.styleFrom(
                                foregroundColor:
                                    selectedTheme.colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppThemeConfig _currentTheme() {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }

  Widget _buildStatsGrid(AppThemeConfig selectedTheme) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            selectedTheme,
            'Skor',
            widget.result.finalScore.toString(),
            selectedTheme.colors.accent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            selectedTheme,
            'Kelime',
            widget.result.totalWords.toString(),
            selectedTheme.colors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            selectedTheme,
            'Max Combo',
            'x${widget.result.maxCombo}',
            selectedTheme.colors.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    AppThemeConfig selectedTheme,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.38)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          if (label == 'Skor') ...[
            const SizedBox(height: 2),
            Text(
              _isNewBest ? 'New best' : 'Best: $_bestScore',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isNewBest
                    ? selectedTheme.colors.accent
                    : Colors.white.withOpacity(0.62),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
