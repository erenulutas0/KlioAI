import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/nf_tokens.dart';

/// A rounded progress track with a rounded fill.
///
/// Two heights are in use: [NfSize.progressProminent] (10px) for the things a
/// learner is meant to look at — daily goal, XP, lesson completion — and
/// [NfSize.progressQuiet] (4px) for progress that is only context, such as a
/// word's strength inside a list row.
class NfProgressBar extends StatelessWidget {
  const NfProgressBar({
    super.key,
    required this.value,
    this.height = NfSize.progressProminent,
    this.fillColor,
    this.trackColor,
    this.animate = true,
    this.semanticsLabel,
  });

  /// 0..1. Values outside the range are clamped rather than asserted, because
  /// this is fed by live counters (XP, words due) that can briefly overshoot.
  final double value;

  final double height;

  /// Defaults to [NfTokens.primary]; pass a semantic token for goal states.
  final Color? fillColor;

  /// Defaults to [NfTokens.border].
  final Color? trackColor;

  final bool animate;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final double target = value.isNaN ? 0 : value.clamp(0.0, 1.0);

    final BoxDecoration trackDecoration = BoxDecoration(
      color: trackColor ?? t.border,
      borderRadius: NfRadius.pillAll,
    );
    final BoxDecoration fillDecoration = BoxDecoration(
      color: fillColor ?? t.primary,
      borderRadius: NfRadius.pillAll,
    );

    Widget barFor(double fraction) {
      return SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(decoration: trackDecoration),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: DecoratedBox(decoration: fillDecoration),
              ),
            ),
          ],
        ),
      );
    }

    final Widget bar = animate
        ? TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: target),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double fraction, Widget? _) =>
                barFor(fraction),
          )
        : barFor(target);

    if (semanticsLabel == null) {
      return bar;
    }
    return Semantics(
      label: semanticsLabel,
      value: '${(target * 100).round()}%',
      child: bar,
    );
  }
}

/// Five dots showing how well a word is known.
///
/// [strength] is the SRS level, 0 (brand new) through [total] (mastered).
class NfStrengthDots extends StatelessWidget {
  const NfStrengthDots({
    super.key,
    required this.strength,
    this.total = 5,
    this.size = NfSize.strengthDot,
    this.gap = NfSpace.s4,
    this.color,
  });

  final int strength;
  final int total;
  final double size;
  final double gap;

  /// Defaults to [NfTokens.primary]. A mastery screen may pass a semantic
  /// token so the ramp reads at a glance.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final int filled = strength.clamp(0, total);
    final Color on = color ?? t.primary;

    return Semantics(
      label: context
          .tr('words.strength')
          .replaceAll('{n}', '$filled')
          .replaceAll('{total}', '$total'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < total; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: i < filled ? on : t.border,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
