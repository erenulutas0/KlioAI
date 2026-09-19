import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../nf_shell.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import 'nf_landing_page.dart';

/// What a new learner meets instead of a sign-in screen.
///
/// The app opened on "continue with Google". Firebase counted 235 people opening
/// it in a month against 40 accounts created, and of 105 accounts only 11 ever
/// opened the app on a second day — most people left at the door, before the
/// tutor had said anything. Somebody who arrives from a fifteen-second video of
/// a conversation should be in a conversation, not in an account form.
///
/// So this screen asks the server for a guest account and goes straight to the
/// tutor. It is a real account, so nothing downstream needs to know; signing in
/// later converts that same row and keeps everything in it. If the server cannot
/// be reached, the old sign-in screen is still there — a learner with no network
/// is no worse off than before.
class NfGuestGate extends StatefulWidget {
  const NfGuestGate({super.key, this.authService});

  /// Injected by the tests; the app uses the singleton.
  final AuthService? authService;

  @override
  State<NfGuestGate> createState() => _NfGuestGateState();
}

class _NfGuestGateState extends State<NfGuestGate> {
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final AuthService auth = widget.authService ?? AuthService();
    final String locale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final bool started =
        await auth.isLoggedIn() || await auth.startGuestSession(locale: locale);
    if (!mounted) {
      return;
    }

    if (!started) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const NfLandingPage()),
      );
      return;
    }

    final Map<String, dynamic>? user = await auth.getUser();
    if (!mounted) {
      return;
    }
    if (user != null) {
      context.read<AppStateProvider>().setUser(user);
    }
    unawaited(AnalyticsService.logEvent('guest_session_started'));
    // The tutor rather than today's plan: the conversation is the thing the app
    // is downloaded for, and a guest has no plan yet to look at.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const NfShell(initialIndex: NfShell.tutorTab),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NfThemeScope(
      child: Builder(
        builder: (BuildContext context) {
          final NfTokens t = NfTokens.of(context);
          return Scaffold(
            backgroundColor: t.ground,
            body: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: NfStroke.border,
                  color: t.primary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
