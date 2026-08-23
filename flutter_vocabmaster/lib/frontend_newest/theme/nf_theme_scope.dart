import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../nf_frontend_preference.dart';
import 'nf_theme.dart';
import 'nf_tokens.dart';

/// Installs the new frontend's palette over [child].
///
/// `NfShell` is not the only place that needs this. A route pushed from the
/// shell is built under the app's [Navigator], which sits *above* the shell, so
/// it inherits none of the shell's [NfTheme] — `NfTokens.of` would silently
/// fall back to the device brightness and ignore the learner's in-app choice.
/// Every new-frontend page that is pushed rather than hosted in a tab wraps
/// itself in this.
class NfThemeScope extends StatefulWidget {
  const NfThemeScope({super.key, required this.child});

  final Widget child;

  @override
  State<NfThemeScope> createState() => _NfThemeScopeState();
}

class _NfThemeScopeState extends State<NfThemeScope> {
  Brightness? _themedBrightness;
  ThemeData? _materialTheme;

  /// Cached because a [ThemeData] here means rebuilding a dozen Google Fonts
  /// text styles, and this rebuilds whenever the host does.
  ThemeData _themeFor(Brightness brightness) {
    if (_materialTheme == null || _themedBrightness != brightness) {
      _themedBrightness = brightness;
      _materialTheme = NfTheme.materialTheme(brightness);
    }
    return _materialTheme!;
  }

  @override
  Widget build(BuildContext context) {
    final NfFrontendPreference preference =
        context.watch<NfFrontendPreference>();
    final Brightness brightness =
        preference.brightnessFor(MediaQuery.platformBrightnessOf(context));
    final NfTokens tokens = NfTokens.resolve(brightness);
    final bool isDark = brightness == Brightness.dark;

    return NfTheme(
      tokens: tokens,
      // Material still paints the scrollbars, spinners, text selection and
      // dialogs inside these pages; without this they would come through in
      // the current app's dark blue.
      child: Theme(
        data: _themeFor(brightness),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: NfTokens.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: tokens.surface,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
