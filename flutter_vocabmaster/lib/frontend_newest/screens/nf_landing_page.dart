import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../providers/app_state_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';

/// The flat white K — the same file the Android launch drawable and
/// `SplashScreen` draw, so the mark a learner has been looking at since the
/// cold start does not change shape when this screen takes over.
const String _kMarkAsset = 'assets/images/flat_k_white.png';

/// Side of the violet tile the mark sits on. The asset is an adaptive-icon
/// foreground: the glyph itself covers roughly half of it, and that built-in
/// margin is what gives the tile its app-icon proportions.
const double _kMarkSize = 88;

/// Stops the column from stretching across a tablet. Same value the previous
/// login screen used.
const double _kMaxContentWidth = 420;

/// The pre-sign-in screen, in the new design.
///
/// Replaces the pair the app used to show here (`LandingPage` pushing
/// `LoginPage`): there was never anything on the first of the two but a promise
/// and a button that opened the second one, so they are one screen now.
///
/// Nothing about signing in changed. [AuthService.googleLogin] is still the
/// only call, its result still carries the message
/// `GoogleLoginErrorMessageFormatter` produced (including the cancellation
/// line), and success still hands the user to [AppStateProvider] and lands on
/// [MainScreen] — or on [onLoginSuccess] when the caller supplied one.
///
/// This runs before the shell exists, so it installs [NfThemeScope] itself
/// rather than inheriting a palette from a host that has not been built yet.
class NfLandingPage extends StatelessWidget {
  const NfLandingPage({super.key, this.onLoginSuccess});

  /// Called instead of pushing [MainScreen] once sign-in succeeds. Carried over
  /// from the old `LoginPage` so an embedder that wants to keep the navigator
  /// to itself still can.
  final VoidCallback? onLoginSuccess;

  @override
  Widget build(BuildContext context) {
    return NfThemeScope(child: _NfLandingView(onLoginSuccess: onLoginSuccess));
  }
}

/// The screen proper. Split from [NfLandingPage] so that every `NfTokens.of`
/// below reads the palette [NfThemeScope] installs, rather than the one above
/// it.
class _NfLandingView extends StatefulWidget {
  const _NfLandingView({this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  State<_NfLandingView> createState() => _NfLandingViewState();
}

class _NfLandingViewState extends State<_NfLandingView> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleLogin() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);

    final AuthService auth = AuthService();
    final Map<String, dynamic> result = await auth.googleLogin();

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (result['success'] == true) {
      await AnalyticsService.logLoginCompleted(
        method: 'google',
        userId: _extractUserId(result),
      );

      if (!mounted) return;
      final Object? user = result['user'];
      if (user is Map<String, dynamic>) {
        context.read<AppStateProvider>().setUser(user);
      } else if (user is Map) {
        context
            .read<AppStateProvider>()
            .setUser(Map<String, dynamic>.from(user));
      }

      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const MainScreen()),
        );
      }
      return;
    }

    // Everything that is not a success arrives here, cancellation included:
    // `AuthService.googleLogin` returns its own line for a dismissed sheet and
    // `GoogleLoginErrorMessageFormatter`'s for a real failure. Both are already
    // written for a learner to read, so the screen shows them as they are.
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (result['message'] as String?) ?? context.tr('login.error.google'),
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.wrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _extractUserId(Map<String, dynamic> result) {
    final Object? user = result['user'];
    if (user is Map) {
      final Object? id = user['id'] ?? user['userId'];
      if (id != null) return id.toString();
    }
    final Object? id = result['userId'] ?? result['id'];
    return id?.toString();
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    // Vertical padding is subtracted from the min height so that `Center` gets
    // the height the column can actually occupy. Without it the content is a
    // padding's worth taller than the viewport and every phone scrolls a screen
    // that fits.
    const EdgeInsets padding = EdgeInsets.fromLTRB(
      NfSpace.s20,
      NfSpace.s20,
      NfSpace.s20,
      NfSpace.s26,
    );

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      math.max(0, constraints.maxHeight - padding.vertical),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _kMaxContentWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Center(child: _Mark()),
                        const SizedBox(height: NfSpace.s16),
                        Text(
                          context.tr('app.name'),
                          textAlign: TextAlign.center,
                          style:
                              NfTokens.display(size: NfFont.s25, color: t.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: NfSpace.s8),
                        Text(
                          context.tr('auth.tagline'),
                          textAlign: TextAlign.center,
                          style: NfTokens.body(
                            size: NfFont.s15,
                            color: t.inkMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: NfSpace.s22),
                        const _ValueCard(),
                        const SizedBox(height: NfSpace.s20),
                        Text(
                          context.tr('auth.sync'),
                          textAlign: TextAlign.center,
                          style: NfTokens.body(
                            size: NfFont.s125,
                            color: t.inkMuted,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: NfSpace.s12),
                        NfPrimaryButton(
                          // While the sheet is up the face is a spinner, so
                          // this label is what a screen reader announces — the
                          // one place the "checking" line is still spoken.
                          label: _isSigningIn
                              ? context.tr('auth.google.checking')
                              : context.tr('login.social.google'),
                          icon: LucideIcons.logIn,
                          busy: _isSigningIn,
                          onPressed: _handleGoogleLogin,
                        ),
                        const SizedBox(height: NfSpace.s12),
                        Text(
                          context.tr('auth.noPassword'),
                          textAlign: TextAlign.center,
                          style: NfTokens.body(
                            size: NfFont.s12,
                            color: t.inkFaint,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK
// ═══════════════════════════════════════════════════════════════════════════

/// The K on its violet tile.
///
/// The asset is white on transparent, so the tile is not decoration: it is the
/// only thing that makes the mark visible, and it is the same violet the splash
/// hands over from. Decorative to a screen reader — the wordmark underneath
/// already says the name.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Container(
      width: _kMarkSize,
      height: _kMarkSize,
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: NfRadius.cardAll,
      ),
      child: const Image(
        image: AssetImage(_kMarkAsset),
        width: _kMarkSize,
        height: _kMarkSize,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WHAT THE APP IS
// ═══════════════════════════════════════════════════════════════════════════

/// Three lines about what happens after signing in.
///
/// This is what is left of the old landing page's rotating feature carousel and
/// its stat grid ("5K+ active users", "99% satisfaction"). The carousel moved on
/// its own timer, so a learner reading one panel lost it mid-sentence, and the
/// numbers were claims nothing in the app could back. Three fixed rows say the
/// same thing and stay still long enough to be read.
class _ValueCard extends StatelessWidget {
  const _ValueCard();

  @override
  Widget build(BuildContext context) {
    return NfCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ValueRow(
            icon: LucideIcons.sparkles,
            title: context.tr('auth.value.daily.title'),
            description: context.tr('auth.value.daily.desc'),
          ),
          const SizedBox(height: NfSpace.s14),
          _ValueRow(
            icon: LucideIcons.repeat,
            title: context.tr('auth.value.review.title'),
            description: context.tr('auth.value.review.desc'),
          ),
          const SizedBox(height: NfSpace.s14),
          _ValueRow(
            icon: LucideIcons.messageCircle,
            title: context.tr('auth.value.tutor.title'),
            description: context.tr('auth.value.tutor.desc'),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  static const double _tileSize = 40;

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: _tileSize,
          height: _tileSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.primarySoft,
            borderRadius: NfRadius.iconTileAll,
            border: Border.fromBorderSide(t.sideOf(t.primary)),
          ),
          child: Icon(icon, size: 20, color: t.primaryText),
        ),
        const SizedBox(width: NfSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: NfTokens.body(
                  size: NfFont.s15,
                  weight: NfTokens.bodyEmphasisWeight,
                  color: t.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: NfSpace.s4),
              Text(
                description,
                style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
