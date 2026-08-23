import 'package:flutter/material.dart';

import '../theme/nf_tokens.dart';

/// The 2px-bordered, 20-radius surface that nearly every block in the new
/// frontend sits on.
///
/// Borders carry the structure here, so there is no elevation and no shadow.
/// A tappable card answers with a small scale-down instead of a ripple.
class NfCard extends StatefulWidget {
  const NfCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.clipContent = false,
  });

  final Widget child;

  /// Defaults to [NfSpace.cardPadding]. Pass [EdgeInsets.zero] for a card whose
  /// content already handles its own insets.
  final EdgeInsetsGeometry? padding;

  final VoidCallback? onTap;

  /// Defaults to [NfTokens.surface]. Semantic cards pass a soft token
  /// (correctSoft / wrongSoft / streakSoft / primarySoft).
  final Color? backgroundColor;

  /// Defaults to [NfTokens.border].
  final Color? borderColor;

  /// Defaults to [NfRadius.cardAll]; small tiles pass [NfRadius.tileAll].
  final BorderRadius? borderRadius;

  /// Clip children to the rounded corners. Needed when content runs flush to
  /// the edge (a full-bleed progress bar, an image header).
  final bool clipContent;

  @override
  State<NfCard> createState() => _NfCardState();
}

class _NfCardState extends State<NfCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final BorderRadius radius = widget.borderRadius ?? NfRadius.cardAll;

    Widget content = Padding(
      padding: widget.padding ?? NfSpace.cardPadding,
      child: widget.child,
    );

    if (widget.clipContent) {
      content = ClipRRect(borderRadius: radius, child: content);
    }

    final Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? t.surface,
        borderRadius: radius,
        border: Border.fromBorderSide(
          widget.borderColor == null ? t.side : t.sideOf(widget.borderColor!),
        ),
      ),
      child: content,
    );

    if (widget.onTap == null) {
      return card;
    }

    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: card,
          ),
        ),
      ),
    );
  }
}
