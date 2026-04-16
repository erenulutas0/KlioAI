import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';

class NeuralCenterNode extends StatelessWidget {
  final String word;
  final String subtitle;
  final int timeLeft;
  final double progress;

  const NeuralCenterNode({
    super.key,
    required this.word,
    required this.subtitle,
    required this.timeLeft,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(150, 150),
            painter: _CircularTimerPainter(
              progress: progress,
              startColor: selectedTheme.colors.accent,
              endColor: selectedTheme.colors.primary,
            ),
          ),
          Container(
            width: 126,
            height: 126,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selectedTheme.colors.buttonGradient,
              border: Border.all(
                color: selectedTheme.colors.accent.withOpacity(0.8),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: selectedTheme.colors.accentGlow.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.28),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      word,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 23,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${timeLeft}s',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

class _CircularTimerPainter extends CustomPainter {
  final double progress;
  final Color startColor;
  final Color endColor;

  const _CircularTimerPainter({
    required this.progress,
    required this.startColor,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      colors: [startColor, endColor],
      startAngle: -pi / 2,
      endAngle: 3 * pi / 2,
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularTimerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}
