import 'package:flutter/material.dart';

enum ThemeParticleStyle {
  rain,
  neural,
  float,
  pulse,
  energy,
}

class ThemeColors {
  final Color background;
  final LinearGradient backgroundGradient;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color accentGlow;
  final Color glassBackground;
  final Color glassBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color cardBackground;
  final Color cardBorder;
  final LinearGradient buttonGradient;
  final Color particleColor;
  final Color particleGlow;
  final Color orbColor1;
  final Color orbColor2;

  const ThemeColors({
    required this.background,
    required this.backgroundGradient,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.accentGlow,
    required this.glassBackground,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.cardBackground,
    required this.cardBorder,
    required this.buttonGradient,
    required this.particleColor,
    required this.particleGlow,
    required this.orbColor1,
    required this.orbColor2,
  });
}

class ThemeAnimations {
  final ThemeParticleStyle particleStyle;
  final int particleCount;
  final String glowIntensity;
  final bool backgroundMotion;
  final int transitionDurationMs;

  const ThemeAnimations({
    required this.particleStyle,
    required this.particleCount,
    required this.glowIntensity,
    required this.backgroundMotion,
    required this.transitionDurationMs,
  });
}

class AppThemeConfig {
  final String id;
  final String name;
  final String iconLabel;
  final bool isPremium;
  final int xpRequired;
  final String description;
  final ThemeColors colors;
  final ThemeAnimations animations;

  const AppThemeConfig({
    required this.id,
    required this.name,
    required this.iconLabel,
    required this.isPremium,
    required this.xpRequired,
    required this.description,
    required this.colors,
    required this.animations,
  });
}
