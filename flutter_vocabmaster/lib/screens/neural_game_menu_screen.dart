import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/neural_game_mode.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../widgets/neural/glassmorphism_card.dart';
import '../widgets/neural/neural_ai_indicator.dart';
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
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: GlassmorphismCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const NeuralAiIndicator(),
                          const SizedBox(height: 18),
                          _buildNeuralCore(selectedTheme),
                          const SizedBox(height: 20),
                          ShaderMask(
                            shaderCallback: (bounds) => selectedTheme
                                .colors.buttonGradient
                                .createShader(bounds),
                            child: Text(
                              'Neural Word Network',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.orbitron(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Center word etrafinda anlam agini olustur. 60 saniyede en yuksek skoru yap.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildModeSelector(selectedTheme),
                          const SizedBox(height: 16),
                          _buildInfoTile(selectedTheme, 'Sure', '60 saniye'),
                          _buildInfoTile(
                            selectedTheme,
                            'Puan',
                            'Base 100 + combo carpan',
                          ),
                          _buildInfoTile(
                            selectedTheme,
                            'Hedef',
                            _selectedMode == NeuralGameMode.relatedWords
                                ? 'Iliskili kelimelerle agi tamamla'
                                : 'Kelimelerin Turkce karsiliklarini bul',
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              gradient: selectedTheme.colors.buttonGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => widget.onStart(_selectedMode),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Oyunu Baslat'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Pratik ekranina don'),
                            style: TextButton.styleFrom(
                              foregroundColor: selectedTheme.colors.textSecondary,
                            ),
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

  Widget _buildNeuralCore(AppThemeConfig selectedTheme) {
    return SizedBox(
      width: 260,
      height: 260,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++) _buildRing(i, selectedTheme),
              Container(
                width: 110,
                height: 110,
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
                child: const Icon(
                  Icons.hub_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRing(int index, AppThemeConfig selectedTheme) {
    final delay = index / 3;
    final value = (_controller.value + delay) % 1.0;
    final scale = 0.7 + (value * 0.8);
    final opacity = (0.35 - value * 0.25).clamp(0.04, 0.35);

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 170,
        height: 170,
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
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.chevron_right_rounded,
            color: selectedTheme.colors.accent.withOpacity(0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(AppThemeConfig selectedTheme) {
    return Row(
      children: [
        Expanded(
          child: _buildModeCard(
            selectedTheme: selectedTheme,
            mode: NeuralGameMode.relatedWords,
            title: 'Iliskili Kelime',
            subtitle: 'Ingilizce baglantili kelime yaz',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildModeCard(
            selectedTheme: selectedTheme,
            mode: NeuralGameMode.turkishTranslation,
            title: 'Turkce Karsilik',
            subtitle: 'Turkce anlami yaz',
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required AppThemeConfig selectedTheme,
    required NeuralGameMode mode,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedMode == mode;
    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
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
                  color: selected ? selectedTheme.colors.accent : Colors.white54,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
