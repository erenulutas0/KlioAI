import 'package:flutter/material.dart';

class AppColors {
  // Legacy login/theme palette (used across existing screens)
  static const cyan400 = Color(0xFF22D3EE);
  static const cyan500 = Color(0xFF06B6D4);
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue900 = Color(0xFF1E3A8A);
  static const blue950 = Color(0xFF172554);
  static const indigo950 = Color(0xFF1E1B4B);

  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);

  // Modern card/shared widget aliases (kept for backward compatibility)
  static const cardBackgroundDark = Color(0xFF0A1628);
  static const cardBackgroundMedium = Color(0xFF102038);
  static const cardBorderCyan = Color(0xFF22D3EE);
  static const cardBorderBlue = Color(0xFF3B82F6);
  static const shadowDark = Color(0xFF050A14);
  static const textWhite = Colors.white;
  static const textSlate200 = Color(0xFFE2E8F0);
  static const textSlate400 = Color(0xFF94A3B8);

  // Neural game palette
  static const background = Color(0xFF0B0F1A);
  static const primaryGlow = Color(0xFF5B8CFF);
  static const secondaryGlow = Color(0xFF9C5BFF);
  static const accentCyan = Color(0xFF00F5D4);
  static const accentPurple = Color(0xFF8B5CF6);

  static const errorRed = Color(0xFFFF4D6D);
  static const successGreen = Color(0xFF2EF57B);

  static final Color glassWhite = Colors.white.withOpacity(0.06);
  static final Color borderGlow = Colors.white.withOpacity(0.14);

  static Color withOpacity(Color color, double opacity) {
    return color.withOpacity(opacity);
  }

  static final cyan400_50 = cyan400.withOpacity(0.5);
  static final cyan400_70 = cyan400.withOpacity(0.7);
  static final cyan500_20 = cyan500.withOpacity(0.2);
  static final cyan500_30 = cyan500.withOpacity(0.3);
  static final blue500_20 = blue500.withOpacity(0.2);
  static final slate900_30 = slate900.withOpacity(0.3);
  static final slate900_50 = slate900.withOpacity(0.5);
  static final slate900_60 = slate900.withOpacity(0.6);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [blue950, indigo950, blue900],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan500, blue500],
  );

  static const LinearGradient purplePinkGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanBlueGradient = LinearGradient(
    colors: [Color(0xFF00F5D4), Color(0xFF5B8CFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkBackdropGradient = LinearGradient(
    colors: [Color(0xFF0B0F1A), Color(0xFF111B2E), Color(0xFF1A1D3A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
