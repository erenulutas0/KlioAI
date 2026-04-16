import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';
import 'glassmorphism_card.dart';

class NeuralComboMeter extends StatelessWidget {
  final int combo;

  const NeuralComboMeter({
    super.key,
    required this.combo,
  });

  @override
  Widget build(BuildContext context) {
    final isHot = combo >= 3;
    final selectedTheme = _currentTheme(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        boxShadow: isHot
            ? [
                BoxShadow(
                  color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: GlassmorphismCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderRadius: 16,
        color: selectedTheme.colors.accent.withOpacity(0.12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMBO',
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'x$combo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (isHot) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.local_fire_department,
                    color: selectedTheme.colors.accent,
                    size: 18,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  AppThemeConfig _currentTheme(BuildContext context) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: true)?.currentTheme ??
          VocabThemes.defaultTheme;
    } catch (_) {
      return VocabThemes.defaultTheme;
    }
  }
}
