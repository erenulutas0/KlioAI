import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';

class GlassmorphismCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blurAmount;
  final Color? color;

  const GlassmorphismCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 22,
    this.blurAmount = 12,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? selectedTheme.colors.glassBackground,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: selectedTheme.colors.glassBorder.withOpacity(0.92),
              width: 1,
            ),
          ),
          child: child,
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
