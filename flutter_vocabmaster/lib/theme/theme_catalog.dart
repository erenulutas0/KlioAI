import 'package:flutter/material.dart';
import 'app_theme.dart';

class VocabThemes {
  VocabThemes._();

  static final List<AppThemeConfig> all = [
    AppThemeConfig(
      id: 'ice_blue',
      name: 'Ice Blue',
      iconLabel: 'ICE',
      isPremium: false,
      xpRequired: 0,
      description: 'Clean and educational look',
      colors: ThemeColors(
        background: const Color(0xFF0A1628),
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFF0A1628),
            Color(0xFF1E3A5F),
            Color(0xFF0A1628),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        primary: const Color(0xFF3B82F6),
        primaryLight: const Color(0xFF60A5FA),
        primaryDark: const Color(0xFF2563EB),
        accent: const Color(0xFF06B6D4),
        accentGlow: const Color(0xFF06B6D4).withOpacity(0.4),
        glassBackground: Colors.white.withOpacity(0.05),
        glassBorder: Colors.white.withOpacity(0.1),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFF94A3B8),
        textMuted: const Color(0xFF64748B),
        cardBackground: const Color(0xFF3B82F6).withOpacity(0.1),
        cardBorder: const Color(0xFF3B82F6).withOpacity(0.2),
        buttonGradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        particleColor: const Color(0xFF06B6D4).withOpacity(0.6),
        particleGlow: const Color(0xFF06B6D4).withOpacity(0.4),
        orbColor1: const Color(0xFF06B6D4).withOpacity(0.08),
        orbColor2: const Color(0xFF3B82F6).withOpacity(0.04),
      ),
      animations: const ThemeAnimations(
        particleStyle: ThemeParticleStyle.rain,
        particleCount: 40,
        glowIntensity: 'low',
        backgroundMotion: true,
        transitionDurationMs: 500,
      ),
    ),
    AppThemeConfig(
      id: 'neural_glow',
      name: 'Neural Glow',
      iconLabel: 'AI',
      isPremium: true,
      xpRequired: 500,
      description: 'AI-powered neural network theme',
      colors: ThemeColors(
        background: const Color(0xFF0B0F1A),
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFF0B0F1A),
            Color(0xFF1A1F3A),
            Color(0xFF0B0F1A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        primary: const Color(0xFF00F5D4),
        primaryLight: const Color(0xFF5DFDEE),
        primaryDark: const Color(0xFF00C9B0),
        accent: const Color(0xFF5B8CFF),
        accentGlow: const Color(0xFF00F5D4).withOpacity(0.6),
        glassBackground: Colors.white.withOpacity(0.03),
        glassBorder: const Color(0xFF00F5D4).withOpacity(0.2),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFFB0E7E0),
        textMuted: const Color(0xFF6B8B9A),
        cardBackground: const Color(0xFF00F5D4).withOpacity(0.05),
        cardBorder: const Color(0xFF00F5D4).withOpacity(0.3),
        buttonGradient: const LinearGradient(
          colors: [Color(0xFF00F5D4), Color(0xFF5B8CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        particleColor: const Color(0xFF00F5D4).withOpacity(0.5),
        particleGlow: const Color(0xFF00F5D4).withOpacity(0.6),
        orbColor1: const Color(0xFF00F5D4).withOpacity(0.1),
        orbColor2: const Color(0xFF5B8CFF).withOpacity(0.06),
      ),
      animations: const ThemeAnimations(
        particleStyle: ThemeParticleStyle.neural,
        particleCount: 30,
        glowIntensity: 'high',
        backgroundMotion: true,
        transitionDurationMs: 600,
      ),
    ),
    AppThemeConfig(
      id: 'midnight_focus',
      name: 'Midnight Focus',
      iconLabel: 'MOON',
      isPremium: true,
      xpRequired: 1000,
      description: 'Elegant and minimal focus mode',
      colors: ThemeColors(
        background: const Color(0xFF0F0A1F),
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFF0F0A1F),
            Color(0xFF2D1B4E),
            Color(0xFF0F0A1F),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        primary: const Color(0xFF8B5CF6),
        primaryLight: const Color(0xFFA78BFA),
        primaryDark: const Color(0xFF7C3AED),
        accent: const Color(0xFFEC4899),
        accentGlow: const Color(0xFF8B5CF6).withOpacity(0.45),
        glassBackground: Colors.white.withOpacity(0.04),
        glassBorder: const Color(0xFF8B5CF6).withOpacity(0.2),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFFD1C4E9),
        textMuted: const Color(0xFFA78BFA),
        cardBackground: const Color(0xFF8B5CF6).withOpacity(0.08),
        cardBorder: const Color(0xFF8B5CF6).withOpacity(0.24),
        buttonGradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        particleColor: const Color(0xFFB48BFF).withOpacity(0.55),
        particleGlow: const Color(0xFF8B5CF6).withOpacity(0.45),
        orbColor1: const Color(0xFF8B5CF6).withOpacity(0.12),
        orbColor2: const Color(0xFFEC4899).withOpacity(0.06),
      ),
      animations: const ThemeAnimations(
        particleStyle: ThemeParticleStyle.float,
        particleCount: 25,
        glowIntensity: 'medium',
        backgroundMotion: true,
        transitionDurationMs: 500,
      ),
    ),
    AppThemeConfig(
      id: 'emerald_calm',
      name: 'Emerald Calm',
      iconLabel: 'LEAF',
      isPremium: true,
      xpRequired: 1500,
      description: 'Relaxed and focus-friendly visuals',
      colors: ThemeColors(
        background: const Color(0xFF0A1F1A),
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFF0A1F1A),
            Color(0xFF1A4D3F),
            Color(0xFF0A1F1A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        primary: const Color(0xFF10B981),
        primaryLight: const Color(0xFF34D399),
        primaryDark: const Color(0xFF059669),
        accent: const Color(0xFF14B8A6),
        accentGlow: const Color(0xFF10B981).withOpacity(0.42),
        glassBackground: Colors.white.withOpacity(0.04),
        glassBorder: const Color(0xFF10B981).withOpacity(0.2),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFFB7E4D9),
        textMuted: const Color(0xFF7BC7B1),
        cardBackground: const Color(0xFF10B981).withOpacity(0.08),
        cardBorder: const Color(0xFF10B981).withOpacity(0.22),
        buttonGradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF14B8A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        particleColor: const Color(0xFF34D399).withOpacity(0.55),
        particleGlow: const Color(0xFF10B981).withOpacity(0.35),
        orbColor1: const Color(0xFF10B981).withOpacity(0.12),
        orbColor2: const Color(0xFF14B8A6).withOpacity(0.06),
      ),
      animations: const ThemeAnimations(
        particleStyle: ThemeParticleStyle.pulse,
        particleCount: 20,
        glowIntensity: 'medium',
        backgroundMotion: true,
        transitionDurationMs: 500,
      ),
    ),
    AppThemeConfig(
      id: 'solar_energy',
      name: 'Solar Energy',
      iconLabel: 'SUN',
      isPremium: true,
      xpRequired: 2000,
      description: 'Energetic and dynamic high-contrast look',
      colors: ThemeColors(
        background: const Color(0xFF1F0A0A),
        backgroundGradient: const LinearGradient(
          colors: [
            Color(0xFF1F0A0A),
            Color(0xFF4D1A1A),
            Color(0xFF1F0A0A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        primary: const Color(0xFFF97316),
        primaryLight: const Color(0xFFFB923C),
        primaryDark: const Color(0xFFEA580C),
        accent: const Color(0xFFEF4444),
        accentGlow: const Color(0xFFF97316).withOpacity(0.52),
        glassBackground: Colors.white.withOpacity(0.04),
        glassBorder: const Color(0xFFF97316).withOpacity(0.24),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFFFCD9BF),
        textMuted: const Color(0xFFF8B88A),
        cardBackground: const Color(0xFFF97316).withOpacity(0.1),
        cardBorder: const Color(0xFFF97316).withOpacity(0.24),
        buttonGradient: const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        particleColor: const Color(0xFFF97316).withOpacity(0.65),
        particleGlow: const Color(0xFFEF4444).withOpacity(0.45),
        orbColor1: const Color(0xFFF97316).withOpacity(0.14),
        orbColor2: const Color(0xFFEF4444).withOpacity(0.07),
      ),
      animations: const ThemeAnimations(
        particleStyle: ThemeParticleStyle.energy,
        particleCount: 35,
        glowIntensity: 'high',
        backgroundMotion: true,
        transitionDurationMs: 600,
      ),
    ),
  ];

  static AppThemeConfig get defaultTheme => all.first;

  static AppThemeConfig byId(String? id) {
    if (id == null || id.trim().isEmpty) {
      return defaultTheme;
    }
    for (final theme in all) {
      if (theme.id == id) {
        return theme;
      }
    }
    return defaultTheme;
  }
}
