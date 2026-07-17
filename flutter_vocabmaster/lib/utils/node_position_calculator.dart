import 'dart:math';

import 'package:flutter/material.dart';

class NodePositionCalculator {
  static Offset calculate({
    required int index,
    required int total,
    required Size screenSize,
    required Offset center,
  }) {
    final safeTotal = total <= 0 ? 1 : total;
    final radiusBase = (min(screenSize.width, screenSize.height) * 0.34)
        .clamp(110.0, 220.0)
        .toDouble();

    final angleStep = (2 * pi) / safeTotal;
    final angle = (index * angleStep) - (pi / 2);

    final ringOffset = index.isEven ? 0.0 : 16.0;
    final radius = radiusBase + ringOffset;

    final rawX = center.dx + radius * cos(angle);
    final rawY = center.dy + radius * sin(angle);

    const horizontalPadding = 78.0;
    const topPadding = 36.0;
    const bottomReservedHeight = 150.0;
    final safeMaxX =
        max(horizontalPadding, screenSize.width - horizontalPadding);
    final safeMaxY = max(topPadding, screenSize.height - bottomReservedHeight);
    final x = rawX.clamp(horizontalPadding, safeMaxX).toDouble();
    final y = rawY.clamp(topPadding, safeMaxY).toDouble();

    return Offset(x, y);
  }
}
