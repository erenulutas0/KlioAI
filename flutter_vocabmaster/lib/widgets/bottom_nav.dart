import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';
import '../l10n/app_localizations.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Color.lerp(selectedTheme.colors.background,
                    selectedTheme.colors.primary, 0.10)!
                .withOpacity(0.86),
            border: Border(
              top: BorderSide(
                color: selectedTheme.colors.accent.withOpacity(0.28),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: selectedTheme.colors.accentGlow.withOpacity(0.16),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildNavItem(
                    Icons.home_rounded,
                    context.tr('nav.home'),
                    0,
                    selectedTheme,
                  ),
                  _buildNavItem(
                    Icons.menu_book_rounded,
                    context.tr('nav.words'),
                    1,
                    selectedTheme,
                  ),
                  _buildCenterNavItem(selectedTheme), // Special Circular Button
                  _buildNavItem(
                    Icons.format_quote_rounded,
                    context.tr('nav.sentences'),
                    3,
                    selectedTheme,
                  ),
                  _buildNavItem(
                    Icons.school_rounded,
                    context.tr('nav.practice'),
                    4,
                    selectedTheme,
                  ),
                ],
              ),
            ),
          ),
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

  Widget _buildCenterNavItem(AppThemeConfig selectedTheme) {
    return GestureDetector(
      onTap: () => onTap(2),
      child: Container(
        height: 56,
        width: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: selectedTheme.colors.buttonGradient,
          boxShadow: [
            BoxShadow(
              color: selectedTheme.colors.accentGlow.withOpacity(0.36),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.menu_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    int index,
    AppThemeConfig selectedTheme,
  ) {
    final isSelected = currentIndex == index;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: isSelected
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            : const EdgeInsets.all(8),
        decoration: isSelected
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(selectedTheme.colors.background,
                            selectedTheme.colors.accent, 0.62)!
                        .withOpacity(0.94),
                    Color.lerp(selectedTheme.colors.background,
                            selectedTheme.colors.primary, 0.62)!
                        .withOpacity(0.94),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: selectedTheme.colors.accentGlow.withOpacity(0.24),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Colors.white
                  : selectedTheme.colors.textSecondary.withOpacity(0.92),
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selectedTheme.colors.textSecondary.withOpacity(0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
