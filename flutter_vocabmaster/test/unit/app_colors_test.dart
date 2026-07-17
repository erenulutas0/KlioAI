import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/utils/app_colors.dart';

void main() {
  test('withOpacity preserves color channels and updates alpha', () {
    final color = AppColors.withOpacity(AppColors.cyan500, 0.42);

    expect(color.r, AppColors.cyan500.r);
    expect(color.g, AppColors.cyan500.g);
    expect(color.b, AppColors.cyan500.b);
    expect(color.a, closeTo(0.42, 0.001));
  });

  test('precomputed translucent aliases use expected alpha values', () {
    expect(AppColors.glassWhite.a, closeTo(0.06, 0.001));
    expect(AppColors.borderGlow.a, closeTo(0.14, 0.001));
    expect(AppColors.cyan400_50.a, closeTo(0.5, 0.001));
    expect(AppColors.cyan400_70.a, closeTo(0.7, 0.001));
    expect(AppColors.cyan500_20.a, closeTo(0.2, 0.001));
    expect(AppColors.cyan500_30.a, closeTo(0.3, 0.001));
    expect(AppColors.blue500_20.a, closeTo(0.2, 0.001));
    expect(AppColors.slate900_30.a, closeTo(0.3, 0.001));
    expect(AppColors.slate900_50.a, closeTo(0.5, 0.001));
    expect(AppColors.slate900_60.a, closeTo(0.6, 0.001));
  });

  test('shared gradients keep stable endpoints and color count', () {
    expect(AppColors.backgroundGradient.begin, Alignment.topCenter);
    expect(AppColors.backgroundGradient.end, Alignment.bottomCenter);
    expect(AppColors.backgroundGradient.colors, hasLength(3));

    expect(AppColors.buttonGradient.begin, Alignment.topLeft);
    expect(AppColors.buttonGradient.end, Alignment.bottomRight);
    expect(AppColors.buttonGradient.colors, [
      AppColors.cyan500,
      AppColors.blue500,
    ]);

    expect(AppColors.darkBackdropGradient.colors, hasLength(3));
  });
}
