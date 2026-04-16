import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'modern_background.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

class ModernCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BackgroundVariant variant;
  final bool showBorder;
  final bool showGlow;
  final BorderRadius? borderRadius;

  const ModernCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.variant = BackgroundVariant.primary,
    this.showBorder = true,
    this.showGlow = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider?>(context, listen: true);
    } catch (_) {
      themeProvider = null;
    }
    final selectedTheme = themeProvider?.currentTheme ?? VocabThemes.defaultTheme;

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: selectedTheme.colors.accentGlow.withOpacity(0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        child: Stack(
          children: [
            // Background
            Positioned.fill(
              child: ModernBackground(
                variant: variant,
              ),
            ),

            // Backdrop Filter (Glassmorphism)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
            ),

            // Border
            if (showBorder)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius ?? BorderRadius.circular(24),
                    border: Border.all(
                      color: selectedTheme.colors.glassBorder.withOpacity(0.85),
                      width: 1,
                    ),
                  ),
                ),
              ),

            // Content
            Padding(
              padding: padding ?? const EdgeInsets.all(24),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

