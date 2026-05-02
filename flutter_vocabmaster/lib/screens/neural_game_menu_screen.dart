import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/neural_game_mode.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/neural/glassmorphism_card.dart';
import '../widgets/neural/neural_particle_background.dart';

class NeuralGameMenuScreen extends StatefulWidget {
  final ValueChanged<NeuralGameMode> onStart;
  final VoidCallback onBack;

  const NeuralGameMenuScreen({
    super.key,
    required this.onStart,
    required this.onBack,
  });

  @override
  State<NeuralGameMenuScreen> createState() => _NeuralGameMenuScreenState();
}

class _NeuralGameMenuScreenState extends State<NeuralGameMenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  NeuralGameMode _selectedMode = NeuralGameMode.relatedWords;

  bool get _isTurkish => Localizations.localeOf(context).languageCode == 'tr';

  String _text(String tr, String en) => _isTurkish ? tr : en;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final verySmall = constraints.maxHeight < 620;
                  final compact = constraints.maxHeight < 740;
                  final cardWidth = math
                      .min(constraints.maxWidth - 24, 420)
                      .clamp(280.0, 420.0)
                      .toDouble();
                  final coreSize = verySmall ? 52.0 : (compact ? 62.0 : 72.0);
                  final titleSize = verySmall ? 18.0 : 20.0;
                  final bodySize = verySmall ? 10.5 : 11.5;
                  final gap = verySmall ? 6.0 : 8.0;

                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 8 : 10),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: cardWidth,
                          child: GlassmorphismCard(
                            borderRadius: 18,
                            padding: EdgeInsets.all(verySmall ? 12 : 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    _buildNeuralCore(selectedTheme, coreSize),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ShaderMask(
                                            shaderCallback: (bounds) =>
                                                selectedTheme
                                                    .colors.buttonGradient
                                                    .createShader(bounds),
                                            child: Text(
                                              'Neural Network',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.orbitron(
                                                color: Colors.white,
                                                fontSize: titleSize,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _text(
                                              '60 saniyede kelime agini tamamla.',
                                              'Build your word network in 60 seconds.',
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.76),
                                              fontSize: bodySize,
                                              height: 1.25,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: gap + 2),
                                _buildModeSelector(selectedTheme, verySmall),
                                SizedBox(height: gap),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInfoTile(
                                        selectedTheme,
                                        _text('Sure', 'Time'),
                                        _text('60 sn', '60 sec'),
                                        verySmall,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _buildInfoTile(
                                        selectedTheme,
                                        _text('Puan', 'Score'),
                                        _text('Combo', 'Combo'),
                                        verySmall,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _buildInfoTile(
                                        selectedTheme,
                                        _text('Hedef', 'Goal'),
                                        _selectedMode ==
                                                NeuralGameMode.relatedWords
                                            ? _text('Ag kur', 'Build links')
                                            : _text('Ceviri', 'Translate'),
                                        verySmall,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: gap + 2),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient:
                                        selectedTheme.colors.buttonGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: verySmall ? 40 : 44,
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          widget.onStart(_selectedMode),
                                      icon: Icon(
                                        Icons.play_arrow_rounded,
                                        size: verySmall ? 18 : 20,
                                      ),
                                      label: Text(
                                        _text('Oyunu Baslat', 'Start Game'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: verySmall ? 13 : 14,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: verySmall ? 2 : 4),
                                SizedBox(
                                  width: double.infinity,
                                  height: verySmall ? 34 : 38,
                                  child: TextButton.icon(
                                    onPressed: widget.onBack,
                                    icon: Icon(
                                      Icons.arrow_back,
                                      size: verySmall ? 15 : 17,
                                    ),
                                    label: Text(
                                      _text(
                                        'Pratik ekranina don',
                                        'Back to practice',
                                      ),
                                      style: TextStyle(
                                        fontSize: verySmall ? 11.5 : 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          selectedTheme.colors.textSecondary,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
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

  Widget _buildNeuralCore(AppThemeConfig selectedTheme, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++) _buildRing(i, selectedTheme, size),
              Container(
                width: size * 0.42,
                height: size * 0.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selectedTheme.colors.buttonGradient,
                  boxShadow: [
                    BoxShadow(
                      color: selectedTheme.colors.accentGlow.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.hub_rounded,
                  color: Colors.white,
                  size: size * 0.32,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRing(int index, AppThemeConfig selectedTheme, double size) {
    final delay = index / 3;
    final value = (_controller.value + delay) % 1.0;
    final scale = 0.7 + (value * 0.8);
    final opacity = (0.35 - value * 0.25).clamp(0.04, 0.35);

    return Transform.scale(
      scale: scale,
      child: Container(
        width: size * 0.64,
        height: size * 0.64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selectedTheme.colors.accent.withOpacity(opacity),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    AppThemeConfig selectedTheme,
    String title,
    String value,
    bool compact,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.045),
        border: Border.all(
          color: selectedTheme.colors.accent.withOpacity(0.18),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 1 : 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selectedTheme.colors.accent,
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(AppThemeConfig selectedTheme, bool compact) {
    return Row(
      children: [
        Expanded(
          child: _buildModeCard(
            selectedTheme: selectedTheme,
            compact: compact,
            mode: NeuralGameMode.relatedWords,
            title: _text('Iliskili Kelime', 'Related Word'),
            subtitle: _text(
              'Ingilizce baglantili kelime yaz',
              'Type an English word with a clear connection',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildModeCard(
            selectedTheme: selectedTheme,
            compact: compact,
            mode: NeuralGameMode.turkishTranslation,
            title: _text('Turkce Karsilik', 'Turkish Meaning'),
            subtitle: _text(
              'Turkce anlami yaz',
              'Write the Turkish meaning',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required AppThemeConfig selectedTheme,
    required bool compact,
    required NeuralGameMode mode,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedMode == mode;
    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? selectedTheme.colors.accent.withOpacity(0.16)
              : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: selected
                ? selectedTheme.colors.accent.withOpacity(0.65)
                : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.circle_outlined,
                  size: 14,
                  color:
                      selected ? selectedTheme.colors.accent : Colors.white54,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 10.5 : 11.5,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 3 : 5),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: compact ? 9.5 : 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
