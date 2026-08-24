import 'package:flutter/material.dart';

import '../theme/nf_tokens.dart';

/// How long the push takes. Short enough to feel mechanical rather than
/// animated.
const Duration _kPressDuration = Duration(milliseconds: 70);

/// The filled call-to-action.
///
/// Sits on a solid 4px slab of [NfTokens.primaryShadow]. Pressing moves the
/// face down onto the slab, which is what gives the direction its "pushable"
/// feel — there is no blur, no ripple and no elevation anywhere.
class NfPrimaryButton extends StatelessWidget {
  const NfPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.height = NfSize.buttonPrimary,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Optional leading icon, drawn at the label's colour.
  final IconData? icon;

  /// Swaps the label for a spinner and swallows taps. The button keeps its
  /// size so the layout does not jump.
  final bool busy;

  /// Fill the available width. Turn off for a button that hugs its label; the
  /// caller must then supply a bounded width.
  final bool expand;

  final double height;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool enabled = onPressed != null && !busy;

    return _NfPushable(
      label: label,
      icon: icon,
      busy: busy,
      expand: expand,
      height: height,
      onPressed: onPressed,
      faceColor: enabled || busy ? t.primary : t.raised,
      shadowColor: enabled || busy ? t.primaryShadow : t.border,
      foreground: enabled || busy ? t.primaryInk : t.inkFaint,
      side: enabled || busy ? null : t.side,
      labelStyle: NfTokens.display(
        size: NfFont.s16,
        color: enabled || busy ? t.primaryInk : t.inkFaint,
      ),
      iconSize: 20,
      compact: false,
    );
  }
}

/// The quieter sibling: a bordered surface on a slab of [NfTokens.borderStrong].
/// Same push, less weight.
class NfSecondaryButton extends StatelessWidget {
  const NfSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.height = NfSize.buttonSecondary,
    this.tone = NfButtonTone.neutral,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final double height;

  /// Colours the label and border without filling the button.
  final NfButtonTone tone;

  /// Narrow horizontal padding, for a button sharing its row with others.
  /// Three buttons across a 393dp phone get about 111dp each, and the roomy
  /// padding plus an icon left "Hard" with roughly 43dp - the label came out
  /// as "Ha…" on a real device.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final bool enabled = onPressed != null && !busy;
    final Color accent = _toneColor(t, tone);

    return _NfPushable(
      label: label,
      icon: icon,
      busy: busy,
      expand: expand,
      height: height,
      onPressed: onPressed,
      faceColor: enabled || busy ? t.surface : t.raised,
      shadowColor: t.borderStrong,
      foreground: enabled || busy ? accent : t.inkFaint,
      side: enabled || busy
          ? t.sideOf(tone == NfButtonTone.neutral ? t.borderStrong : accent)
          : t.side,
      labelStyle: NfTokens.display(
        size: NfFont.s15,
        color: enabled || busy ? accent : t.inkFaint,
      ),
      iconSize: 18,
      compact: compact,
    );
  }

  static Color _toneColor(NfTokens t, NfButtonTone tone) {
    switch (tone) {
      case NfButtonTone.neutral:
        return t.ink;
      case NfButtonTone.primary:
        return t.primaryText;
      case NfButtonTone.correct:
        return t.correct;
      case NfButtonTone.wrong:
        return t.wrong;
    }
  }
}

/// Meaning carried by a secondary button.
enum NfButtonTone { neutral, primary, correct, wrong }

/// Shared machinery for both buttons.
///
/// Layout trick: the column reserves [NfSize.pressDepth] either above or below
/// the face. Unpressed, the gap is at the bottom and the shadow slab shows
/// through it; pressed, the gap moves to the top and the face slides down to
/// cover the slab exactly. The overall box never changes size, so nothing
/// around the button reflows.
class _NfPushable extends StatefulWidget {
  const _NfPushable({
    required this.label,
    required this.icon,
    required this.busy,
    required this.expand,
    required this.height,
    required this.onPressed,
    required this.faceColor,
    required this.shadowColor,
    required this.foreground,
    required this.side,
    required this.labelStyle,
    required this.iconSize,
    required this.compact,
  });

  final String label;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final double height;
  final VoidCallback? onPressed;
  final Color faceColor;
  final Color shadowColor;
  final Color foreground;
  final BorderSide? side;
  final TextStyle labelStyle;
  final double iconSize;

  /// Narrow padding, for a button sharing its row with others. Set by the
  /// caller rather than derived from the width - see the note in build().
  final bool compact;

  @override
  State<_NfPushable> createState() => _NfPushableState();
}

class _NfPushableState extends State<_NfPushable> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _NfPushable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A button that becomes disabled mid-press must not stay stuck down.
    if (!_enabled && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const double depth = NfSize.pressDepth;

    // Told, not measured. This was a LayoutBuilder that shrank the padding when
    // the button was narrow, which read well and broke the Words tab's empty
    // state: `SliverFillRemaining(hasScrollBody: false)` asks its child for an
    // intrinsic height, and a LayoutBuilder cannot answer that — it throws, the
    // sliver comes back with null geometry, and the viewport crashes. That
    // state is the first screen a new learner sees.
    final double horizontalPadding =
        widget.compact ? NfSpace.s10 : NfSpace.s20;

    final Widget face = Container(
      height: widget.height,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: widget.faceColor,
        borderRadius: NfRadius.controlAll,
        border: widget.side == null ? null : Border.fromBorderSide(widget.side!),
      ),
      child: widget.busy ? _spinner() : _content(),
    );

    final Widget stack = Stack(
      children: <Widget>[
        // The slab. Sits exactly one press-depth below the resting face.
        Positioned.fill(
          top: depth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.shadowColor,
              borderRadius: NfRadius.controlAll,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.expand
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: _kPressDuration,
              curve: Curves.easeOut,
              height: _pressed ? depth : 0,
            ),
            face,
            AnimatedContainer(
              duration: _kPressDuration,
              curve: Curves.easeOut,
              height: _pressed ? 0 : depth,
            ),
          ],
        ),
      ],
    );

    final Widget sized = widget.expand
        ? SizedBox(width: double.infinity, child: stack)
        : stack;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor:
            _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: _enabled ? widget.onPressed : null,
          child: sized,
        ),
      ),
    );
  }

  Widget _content() {
    final Widget text = Text(
      widget.label,
      style: widget.labelStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );

    if (widget.icon == null) {
      return text;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(widget.icon, size: widget.iconSize, color: widget.foreground),
        const SizedBox(width: NfSpace.s8),
        Flexible(child: text),
      ],
    );
  }

  Widget _spinner() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: NfStroke.iconHeavy,
        valueColor: AlwaysStoppedAnimation<Color>(widget.foreground),
      ),
    );
  }
}
