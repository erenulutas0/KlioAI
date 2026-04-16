import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'modern_colors.dart';
import '../painters/dot_pattern_painter.dart';
import '../painters/diagonal_lines_painter.dart';
import '../painters/grid_pattern_painter.dart';
import '../theme/app_theme.dart';
import '../theme/theme_catalog.dart';
import '../theme/theme_provider.dart';

enum BackgroundVariant { primary, secondary, accent }

class ModernBackground extends StatefulWidget {
  final BackgroundVariant variant;
  final Widget? child;

  const ModernBackground({
    super.key,
    this.variant = BackgroundVariant.primary,
    this.child,
  });

  @override
  State<ModernBackground> createState() => _ModernBackgroundState();
}

class _ModernBackgroundState extends State<ModernBackground>
    with TickerProviderStateMixin {
  late AnimationController _orb1Controller;
  late AnimationController _orb2Controller;
  late Animation<double> _orb1Animation;
  late Animation<double> _orb2Animation;

  @override
  void initState() {
    super.initState();

    // Orb 1 Animation (8 seconds)
    _orb1Controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);

    _orb1Animation = Tween<double>(begin: 0.3, end: 0.5).animate(
      CurvedAnimation(parent: _orb1Controller, curve: Curves.easeInOut),
    );

    // Orb 2 Animation (10 seconds, delayed)
    _orb2Controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);

    _orb2Animation = Tween<double>(begin: 0.2, end: 0.4).animate(
      CurvedAnimation(parent: _orb2Controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    super.dispose();
  }

  ThemeProvider? _getThemeProvider({required bool listen}) {
    try {
      return Provider.of<ThemeProvider?>(context, listen: listen);
    } catch (_) {
      return null;
    }
  }

  Color _mix(Color from, Color to, double amount) {
    return Color.lerp(from, to, amount) ?? from;
  }

  List<Color> _getGradientColors(AppThemeConfig selectedTheme) {
    switch (widget.variant) {
      case BackgroundVariant.primary:
        return [
          selectedTheme.colors.background.withOpacity(0.94),
          _mix(selectedTheme.colors.background, selectedTheme.colors.primaryDark, 0.50)
              .withOpacity(0.86),
          selectedTheme.colors.background.withOpacity(0.94),
        ];
      case BackgroundVariant.secondary:
        return [
          _mix(selectedTheme.colors.background, selectedTheme.colors.accent, 0.16)
              .withOpacity(0.92),
          _mix(selectedTheme.colors.background, selectedTheme.colors.primary, 0.28)
              .withOpacity(0.84),
          _mix(selectedTheme.colors.background, selectedTheme.colors.accent, 0.16)
              .withOpacity(0.92),
        ];
      case BackgroundVariant.accent:
        return [
          _mix(selectedTheme.colors.background, selectedTheme.colors.accent, 0.34)
              .withOpacity(0.92),
          _mix(selectedTheme.colors.background, selectedTheme.colors.primary, 0.42)
              .withOpacity(0.86),
          _mix(selectedTheme.colors.background, selectedTheme.colors.accent, 0.34)
              .withOpacity(0.92),
        ];
    }
  }

  Color _dotColor(AppThemeConfig selectedTheme) {
    return selectedTheme.colors.accent.withOpacity(0.10);
  }

  Color _lineColor(AppThemeConfig selectedTheme) {
    return selectedTheme.colors.accent.withOpacity(0.04);
  }

  Color _gridColor(AppThemeConfig selectedTheme) {
    return selectedTheme.colors.primary.withOpacity(0.08);
  }

  Color _orb1Color(AppThemeConfig selectedTheme) {
    return selectedTheme.colors.orbColor1;
  }

  Color _orb2Color(AppThemeConfig selectedTheme) {
    return selectedTheme.colors.orbColor2;
  }

  int _transitionDurationMs(AppThemeConfig selectedTheme) {
    return selectedTheme.animations.transitionDurationMs;
  }

  @override
  Widget build(BuildContext context) {
    final selectedTheme =
        _getThemeProvider(listen: true)?.currentTheme ?? VocabThemes.defaultTheme;
    final transitionDurationMs = _transitionDurationMs(selectedTheme);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          // 1. Base Gradient
          Positioned.fill(
            child: AnimatedContainer(
              duration: Duration(milliseconds: transitionDurationMs),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getGradientColors(selectedTheme),
                ),
              ),
            ),
          ),

          // 2. Dot Pattern Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: DotPatternPainter(color: _dotColor(selectedTheme)),
            ),
          ),

          // 3. Diagonal Lines Pattern
          Positioned.fill(
            child: CustomPaint(
              painter: DiagonalLinesPainter(color: _lineColor(selectedTheme)),
            ),
          ),

          // 4. Animated Orb 1 (Top Right)
          Positioned(
            top: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _orb1Animation,
              builder: (context, child) {
                return Opacity(
                  opacity: _orb1Animation.value,
                  child: Container(
                    width: 384,
                    height: 384,
                    decoration: BoxDecoration(
                      color: _orb1Color(selectedTheme),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ),

          // 5. Animated Orb 2 (Bottom Left)
          Positioned(
            bottom: 0,
            left: 0,
            child: AnimatedBuilder(
              animation: _orb2Animation,
              builder: (context, child) {
                return Opacity(
                  opacity: _orb2Animation.value,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      color: _orb2Color(selectedTheme),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ),

          // 6. Grid Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: GridPatternPainter(color: _gridColor(selectedTheme)),
            ),
          ),

          // 7. Vignette Effect
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Colors.transparent,
                  ModernColors.vignetteColor,
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),

          // 8. Child Content
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

