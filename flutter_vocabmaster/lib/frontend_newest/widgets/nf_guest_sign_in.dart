import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../screens/nf_landing_page.dart';
import '../theme/nf_tokens.dart';
import 'nf_button.dart';

/// How often a guest is asked to sign in, and how many times at all.
///
/// The sign-in screen used to be the first thing in the app; now it is offered
/// after the learner has something to keep. That only works if the offer stays
/// an offer: a sheet that comes back every session is the old wall in a slower
/// form.
class NfGuestPromptSchedule {
  const NfGuestPromptSchedule._();

  static const Duration minBetweenAsks = Duration(hours: 20);
  static const int maxAsks = 3;

  static const String lastAskedKey = 'guest_prompt:last_asked';
  static const String askCountKey = 'guest_prompt:asks';

  /// Whether a guest may be asked now. [now] is injected by the tests.
  static Future<bool> shouldAsk({DateTime? now}) async {
    try {
      if (!await AuthService().isGuestSession()) {
        return false;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(askCountKey) ?? 0) >= maxAsks) {
        return false;
      }
      final String? last = prefs.getString(lastAskedKey);
      if (last == null) {
        return true;
      }
      final DateTime? at = DateTime.tryParse(last);
      return at == null || (now ?? DateTime.now()).difference(at) >= minBetweenAsks;
    } catch (e) {
      // Bookkeeping must never put a sheet in front of someone by failing open.
      debugPrint('Guest prompt check skipped: $e');
      return false;
    }
  }

  static Future<void> recordAsked({DateTime? now}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          lastAskedKey, (now ?? DateTime.now()).toIso8601String());
      await prefs.setInt(askCountKey, (prefs.getInt(askCountKey) ?? 0) + 1);
    } catch (e) {
      debugPrint('Guest prompt not recorded: $e');
    }
  }
}

/// "Keep what you have done" — the sign-in ask, after the app has been used.
///
/// Signing in from here converts the guest account the learner has been using
/// rather than opening a second one, so the conversation they just had, the
/// words they kept and their streak all stay where they are. That is the whole
/// reason this is worth asking for, and it is what the sheet says.
class NfGuestSignInSheet extends StatelessWidget {
  const NfGuestSignInSheet({super.key, required this.reason});

  /// Which moment produced the ask, for the analytics event. Not shown.
  final String reason;

  /// Shows the sheet when a guest is due to be asked. Returns whether it was
  /// shown, so a caller with something else to put on screen can hold it back
  /// rather than stack two asks on one conversation.
  static Future<bool> maybeShow(BuildContext context,
      {required String reason}) async {
    if (!await NfGuestPromptSchedule.shouldAsk() || !context.mounted) {
      return false;
    }
    await NfGuestPromptSchedule.recordAsked();
    if (!context.mounted) {
      return false;
    }
    unawaited(AnalyticsService.logEvent(
      'guest_sign_in_offered',
      parameters: <String, Object>{'reason': reason},
    ));
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NfGuestSignInSheet(reason: reason),
    );
    return true;
  }

  Future<void> _signIn(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final bool? signedIn = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => NfLandingPage(
          onLoginSuccess: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (signedIn == true) {
      unawaited(AnalyticsService.logEvent(
        'guest_sign_in_completed',
        parameters: <String, Object>{'reason': reason},
      ));
    }
    navigator.pop(signedIn == true);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          NfSpace.s20, NfSpace.s12, NfSpace.s20, NfSpace.s22),
      decoration: BoxDecoration(
        color: t.ground,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(NfRadius.card)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: NfSpace.s16),
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(NfRadius.pill),
                ),
              ),
            ),
            Text(
              context.tr('guest.signIn.title'),
              style: NfTokens.body(
                  size: NfFont.s18, color: t.ink, weight: FontWeight.w800),
            ),
            const SizedBox(height: NfSpace.s8),
            Text(
              context.tr('guest.signIn.body'),
              style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
            ),
            const SizedBox(height: NfSpace.s16),
            NfPrimaryButton(
              key: const ValueKey<String>('guest-sign-in'),
              // The same words as the sign-in screen it opens.
              label: context.tr('login.social.google'),
              onPressed: () => unawaited(_signIn(context)),
            ),
            TextButton(
              key: const ValueKey<String>('guest-sign-in-later'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                context.tr('guest.signIn.later'),
                style: NfTokens.body(size: NfFont.s14, color: t.inkFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
