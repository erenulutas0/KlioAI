import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/utils/node_position_calculator.dart';

void main() {
  test('keeps visual node centers inside safe bounds on compact screens', () {
    const screenSize = Size(320, 568);
    const center = Offset(160, 244);

    for (var index = 0; index < 14; index++) {
      final position = NodePositionCalculator.calculate(
        index: index,
        total: 14,
        screenSize: screenSize,
        center: center,
      );

      expect(position.dx, greaterThanOrEqualTo(78));
      expect(position.dx, lessThanOrEqualTo(screenSize.width - 78));
      expect(position.dy, greaterThanOrEqualTo(36));
      expect(position.dy, lessThanOrEqualTo(screenSize.height - 150));
    }
  });

  test('keeps visual node centers inside safe bounds on tall screens', () {
    const screenSize = Size(430, 932);
    const center = Offset(215, 401);

    for (var index = 0; index < 18; index++) {
      final position = NodePositionCalculator.calculate(
        index: index,
        total: 18,
        screenSize: screenSize,
        center: center,
      );

      expect(position.dx, greaterThanOrEqualTo(78));
      expect(position.dx, lessThanOrEqualTo(screenSize.width - 78));
      expect(position.dy, greaterThanOrEqualTo(36));
      expect(position.dy, lessThanOrEqualTo(screenSize.height - 150));
    }
  });
}
