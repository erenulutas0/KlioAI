import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_catalog.dart';
import '../../theme/theme_provider.dart';

class NeuralConnectionLines extends StatelessWidget {
  final Offset centerPosition;
  final List<Offset> nodePositions;
  final double animationValue;

  const NeuralConnectionLines({
    super.key,
    required this.centerPosition,
    required this.nodePositions,
    required this.animationValue,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTheme = _currentTheme(context);
    return CustomPaint(
      painter: NeuralConnectionPainter(
        centerPosition: centerPosition,
        nodePositions: nodePositions,
        animationValue: animationValue,
        startColor: selectedTheme.colors.primary,
        endColor: selectedTheme.colors.accent,
      ),
      size: Size.infinite,
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

class NeuralConnectionPainter extends CustomPainter {
  final List<Offset> nodePositions;
  final Offset centerPosition;
  final double animationValue;
  final Color startColor;
  final Color endColor;

  const NeuralConnectionPainter({
    required this.nodePositions,
    required this.centerPosition,
    required this.animationValue,
    required this.startColor,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final nodePosition in nodePositions) {
      final rect = Rect.fromPoints(centerPosition, nodePosition);
      final gradient = LinearGradient(
        colors: [startColor, endColor],
      );

      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(centerPosition.dx, centerPosition.dy)
        ..lineTo(nodePosition.dx, nodePosition.dy);

      final metric = path.computeMetrics().first;
      final drawPath = metric.extractPath(
        0,
        metric.length * animationValue.clamp(0.0, 1.0),
      );

      canvas.drawPath(drawPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant NeuralConnectionPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.nodePositions.length != nodePositions.length ||
        oldDelegate.centerPosition != centerPosition ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}
