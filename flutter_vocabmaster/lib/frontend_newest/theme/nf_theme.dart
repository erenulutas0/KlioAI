import 'package:flutter/material.dart';

import 'nf_tokens.dart';

/// Provides [NfTokens] to the new frontend.
///
/// Install this once, as high as possible — ideally around the whole
/// `frontend_newest` root, or from `MaterialApp.builder` so that pushed routes
/// and dialogs also see it. Widgets read the palette with
/// `NfTokens.of(context)`, which delegates here.
class NfTheme extends InheritedWidget {
  const NfTheme({
    super.key,
    required this.tokens,
    required super.child,
  });

  /// Light palette variant.
  const NfTheme.light({Key? key, required Widget child})
      : this(key: key, tokens: NfTokens.light, child: child);

  /// Dark palette variant.
  const NfTheme.dark({Key? key, required Widget child})
      : this(key: key, tokens: NfTokens.dark, child: child);

  /// Picks the palette for [brightness].
  NfTheme.fromBrightness({
    super.key,
    required Brightness brightness,
    required super.child,
  }) : tokens = NfTokens.resolve(brightness);

  final NfTokens tokens;

  /// The palette in scope, or null when there is no [NfTheme] above [context].
  /// Prefer `NfTokens.of(context)`, which supplies a platform-brightness
  /// fallback instead of null.
  static NfTokens? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NfTheme>()?.tokens;
  }

  /// The palette in scope. Throws if there is no [NfTheme] ancestor; use
  /// `NfTokens.of(context)` unless you specifically want that assertion.
  static NfTokens of(BuildContext context) {
    final NfTokens? tokens = maybeOf(context);
    assert(tokens != null, 'No NfTheme found in context.');
    return tokens ?? NfTokens.light;
  }

  @override
  bool updateShouldNotify(NfTheme oldWidget) => oldWidget.tokens != tokens;

  // ---------------------------------------------------------------------------
  // MaterialApp-level theming.
  //
  // The new frontend paints its own surfaces, but Material still paints the
  // scaffold, text selection, scrollbars, dialogs and the default text colour.
  // This factory keeps those in the same palette so nothing shows through in
  // stock Material blue/grey.
  // ---------------------------------------------------------------------------

  static ThemeData materialTheme(Brightness brightness) {
    final NfTokens t = NfTokens.resolve(brightness);
    final ThemeData base = ThemeData(brightness: brightness);

    return base.copyWith(
      colorScheme: _colorScheme(t),
      scaffoldBackgroundColor: t.ground,
      canvasColor: t.ground,
      dividerColor: t.border,
      // The direction has no ripple: feedback is the 4px push and a border
      // colour change, so Material's ink would fight it.
      splashFactory: NoSplash.splashFactory,
      splashColor: NfTokens.transparent,
      highlightColor: NfTokens.transparent,
      textTheme: _textTheme(t, base.textTheme),
      iconTheme: IconThemeData(color: t.ink, size: 22),
      primaryIconTheme: IconThemeData(color: t.primaryInk, size: 22),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.primary,
        selectionColor: t.primarySoft,
        selectionHandleColor: t.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primary,
        linearTrackColor: t.border,
        circularTrackColor: t.border,
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: t.ground,
        foregroundColor: t.ink,
        surfaceTintColor: NfTokens.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: NfTokens.display(size: NfFont.s18, color: t.ink),
        iconTheme: IconThemeData(color: t.ink, size: 22),
      ),
      dividerTheme: DividerThemeData(
        color: t.border,
        thickness: NfStroke.border,
        space: NfStroke.border,
      ),
    );
  }

  static ThemeData get lightTheme => materialTheme(Brightness.light);
  static ThemeData get darkTheme => materialTheme(Brightness.dark);

  static ColorScheme _colorScheme(NfTokens t) {
    if (t.isDark) {
      return ColorScheme.dark(
        primary: t.primary,
        onPrimary: t.primaryInk,
        primaryContainer: t.primarySoft,
        onPrimaryContainer: t.primaryText,
        secondary: t.primary,
        onSecondary: t.primaryInk,
        surface: t.surface,
        onSurface: t.ink,
        error: t.wrong,
        onError: t.primaryInk,
        outline: t.border,
      );
    }
    return ColorScheme.light(
      primary: t.primary,
      onPrimary: t.primaryInk,
      primaryContainer: t.primarySoft,
      onPrimaryContainer: t.primaryText,
      secondary: t.primary,
      onSecondary: t.primaryInk,
      surface: t.surface,
      onSurface: t.ink,
      error: t.wrong,
      onError: t.primaryInk,
      outline: t.border,
    );
  }

  /// Fredoka for the display slots, Nunito for everything a learner reads in
  /// bulk. Only the slots Material actually falls back to are filled in.
  static TextTheme _textTheme(NfTokens t, TextTheme base) {
    return base.copyWith(
      displayLarge: NfTokens.display(size: NfFont.s25, color: t.ink),
      displayMedium: NfTokens.display(size: NfFont.s23, color: t.ink),
      displaySmall: NfTokens.display(size: NfFont.s22, color: t.ink),
      headlineLarge: NfTokens.display(size: NfFont.s22, color: t.ink),
      headlineMedium: NfTokens.display(size: NfFont.s20, color: t.ink),
      headlineSmall: NfTokens.display(size: NfFont.s18, color: t.ink),
      titleLarge: NfTokens.display(size: NfFont.s17, color: t.ink),
      titleMedium: NfTokens.display(size: NfFont.s16, color: t.ink),
      titleSmall: NfTokens.display(size: NfFont.s14, color: t.ink),
      bodyLarge: NfTokens.body(size: NfFont.s16, color: t.ink),
      bodyMedium: NfTokens.body(size: NfFont.s14, color: t.ink),
      bodySmall: NfTokens.body(size: NfFont.s13, color: t.inkMuted),
      labelLarge: NfTokens.display(size: NfFont.s16, color: t.ink),
      labelMedium: NfTokens.body(
        size: NfFont.s13,
        weight: NfTokens.bodyEmphasisWeight,
        color: t.inkMuted,
      ),
      labelSmall: NfTokens.body(
        size: NfFont.s12,
        weight: NfTokens.bodyEmphasisWeight,
        color: t.inkFaint,
      ),
    );
  }
}

/// Convenience for reading tokens: `context.nf.primary`.
extension NfThemeContext on BuildContext {
  NfTokens get nf => NfTokens.of(this);
}
