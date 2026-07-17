import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/theme/app_theme.dart';
import 'package:vocabmaster/theme/theme_catalog.dart';

void main() {
  test('theme catalog exposes a complete unique theme set', () {
    final themes = VocabThemes.all;

    expect(themes, hasLength(5));
    expect(VocabThemes.defaultTheme.id, themes.first.id);
    expect(themes.map((theme) => theme.id).toSet(), hasLength(themes.length));
    expect(VocabThemes.byId(null), same(VocabThemes.defaultTheme));
    expect(VocabThemes.byId(''), same(VocabThemes.defaultTheme));
    expect(VocabThemes.byId('missing-theme'), same(VocabThemes.defaultTheme));

    for (final theme in themes) {
      expect(theme.id.trim(), isNotEmpty);
      expect(theme.name.trim(), isNotEmpty);
      expect(theme.iconLabel.trim(), isNotEmpty);
      expect(theme.description.trim(), isNotEmpty);
      expect(VocabThemes.byId(theme.id), same(theme));

      if (theme.isPremium) {
        expect(theme.xpRequired, greaterThan(0));
      } else {
        expect(theme.xpRequired, 0);
      }

      _expectReadableColors(theme.colors);
      _expectUsableGradient(theme.colors.backgroundGradient);
      _expectUsableGradient(theme.colors.buttonGradient);
      _expectUsableAnimation(theme.animations);
    }
  });
}

void _expectReadableColors(ThemeColors colors) {
  final colorValues = [
    colors.background,
    colors.primary,
    colors.primaryLight,
    colors.primaryDark,
    colors.accent,
    colors.accentGlow,
    colors.glassBackground,
    colors.glassBorder,
    colors.textPrimary,
    colors.textSecondary,
    colors.textMuted,
    colors.cardBackground,
    colors.cardBorder,
    colors.particleColor,
    colors.particleGlow,
    colors.orbColor1,
    colors.orbColor2,
  ];

  for (final color in colorValues) {
    expect(color.a, inInclusiveRange(0, 1));
    expect(color.r, inInclusiveRange(0, 1));
    expect(color.g, inInclusiveRange(0, 1));
    expect(color.b, inInclusiveRange(0, 1));
  }
}

void _expectUsableGradient(LinearGradient gradient) {
  expect(gradient.colors.length, greaterThanOrEqualTo(2));
  expect(gradient.begin, isNotNull);
  expect(gradient.end, isNotNull);
}

void _expectUsableAnimation(ThemeAnimations animations) {
  expect(animations.particleStyle, isA<ThemeParticleStyle>());
  expect(animations.particleCount, greaterThan(0));
  expect(animations.glowIntensity, isIn(['low', 'medium', 'high']));
  expect(animations.transitionDurationMs, greaterThan(0));
}
