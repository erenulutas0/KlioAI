import 'package:flutter/material.dart';

import '../theme/nf_tokens.dart';

/// What a chip is saying.
enum NfChipVariant {
  /// Idle filter, tag, or metadata.
  unselected,

  /// The active filter / chosen option.
  selected,

  /// Right answer, mastered, done.
  correct,

  /// Wrong answer, missed, overdue.
  wrong,

  /// Streak, daily goal, anything flame-flavoured.
  streak,
}

/// A pill: label, optional leading icon, five colour variants.
///
/// Tappable chips get a [NfSize.minTap] hit area even though the pill itself is
/// shorter — the visual stays compact without breaking the tap-target floor.
class NfChip extends StatelessWidget {
  const NfChip({
    super.key,
    required this.label,
    this.variant = NfChipVariant.unselected,
    this.icon,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final NfChipVariant variant;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Smaller pill for inline status next to a title.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final _NfChipColors c = _colors(t, variant);

    final double height = dense ? 30 : 36;
    final double gutter = dense ? NfSpace.s10 : NfSpace.s12;
    final double fontSize = dense ? NfFont.s12 : NfFont.s13;
    final double iconSize = dense ? 13 : 15;

    final Widget pill = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: gutter),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: NfRadius.pillAll,
        border: Border.fromBorderSide(t.sideOf(c.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: iconSize, color: c.foreground),
            SizedBox(width: dense ? NfSpace.s4 : NfSpace.s6),
          ],
          Text(
            label,
            style: NfTokens.body(
              size: fontSize,
              weight: NfTokens.bodyEmphasisWeight,
              color: c.foreground,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap == null) {
      return pill;
    }

    return Semantics(
      button: true,
      selected: variant == NfChipVariant.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NfSize.minTap),
            child: Center(widthFactor: 1, child: pill),
          ),
        ),
      ),
    );
  }

  static _NfChipColors _colors(NfTokens t, NfChipVariant variant) {
    switch (variant) {
      case NfChipVariant.unselected:
        return _NfChipColors(
          background: t.raised,
          border: t.border,
          foreground: t.inkMuted,
        );
      case NfChipVariant.selected:
        return _NfChipColors(
          background: t.primarySoft,
          border: t.primary,
          foreground: t.primaryText,
        );
      case NfChipVariant.correct:
        return _NfChipColors(
          background: t.correctSoft,
          border: t.correct,
          foreground: t.correct,
        );
      case NfChipVariant.wrong:
        return _NfChipColors(
          background: t.wrongSoft,
          border: t.wrong,
          foreground: t.wrong,
        );
      case NfChipVariant.streak:
        return _NfChipColors(
          background: t.streakSoft,
          border: t.streak,
          foreground: t.streakText,
        );
    }
  }
}

@immutable
class _NfChipColors {
  const _NfChipColors({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}
