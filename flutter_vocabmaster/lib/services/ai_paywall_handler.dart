import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frontend_newest/screens/nf_subscription_page.dart';
import '../frontend_newest/theme/nf_theme_scope.dart';
import '../providers/app_state_provider.dart';
import '../screens/login_page.dart';
import 'ai_error_message_formatter.dart';
import 'analytics_service.dart';
import 'api_service.dart';
import 'auth_service.dart';

class AiPaywallHandler {
  static Future<void> openSubscription(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    await AnalyticsService.logPaywallShown(source: 'ai_access_required');
    if (!context.mounted) {
      return;
    }
    // Wrapped because the route is built under the app's Navigator, above the
    // shell's NfTheme: without the scope the page would resolve its palette
    // from the device brightness and ignore the learner's in-app choice.
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const NfThemeScope(child: NfSubscriptionPage()),
      ),
    );
  }

  static Future<bool> handleIfUpgradeRequired(
    BuildContext context,
    Object error, {
    bool showSnackBar = true,
  }) async {
    if (!context.mounted) {
      return error is ApiUpgradeRequiredException ||
          error is ApiUnauthorizedException;
    }

    if (error is ApiUpgradeRequiredException) {
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiErrorMessageFormatter.forUpgrade(error)),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await openSubscription(context);
      return true;
    }

    if (error is ApiUnauthorizedException) {
      if (_shouldOpenSubscriptionForUnauthorized(error)) {
        if (showSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error.message.isNotEmpty
                    ? error.message
                    : 'Bu ozellik icin abonelik gerekli.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await openSubscription(context);
        return true;
      }

      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message.isNotEmpty
                  ? error.message
                  : 'Oturum suresi doldu. Lutfen tekrar giris yapin.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      context.read<AppStateProvider>().clearSessionState();
      await AuthService().logout();
      if (!context.mounted) {
        return true;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      return true;
    }

    return false;
  }

  /// Decides whether a 401 means "you need to pay" rather than "your session ended".
  ///
  /// The default is deliberately "session problem". Sending a paying subscriber to the
  /// subscription page because their token expired is far more damaging than missing an
  /// upsell, so this only returns true on a positive billing signal.
  ///
  /// Two rules used to break that: a bare `unauthorized` was classed as a paywall, and
  /// Spring's entry point returns exactly `{"error":"Unauthorized"}` with no reason for an
  /// expired JWT — so every expired session opened the subscription page. The other was
  /// `text.contains('ai')`, which matches those two letters anywhere: fail, email,
  /// available, again, domain, maintenance.
  @visibleForTesting
  static bool shouldOpenSubscriptionForUnauthorized(
    ApiUnauthorizedException error,
  ) =>
      _shouldOpenSubscriptionForUnauthorized(error);

  static bool _shouldOpenSubscriptionForUnauthorized(
    ApiUnauthorizedException error,
  ) {
    final text = '${error.reason ?? ''} ${error.message}'.toLowerCase();
    if (text.contains('missing-auth') ||
        text.contains('oturum') ||
        text.contains('session') ||
        text.contains('token') ||
        text.contains('giris') ||
        text.contains('login') ||
        text.contains('expired') ||
        text.contains('suresi')) {
      return false;
    }

    return text.contains('abon') ||
        text.contains('subscription') ||
        text.contains('premium') ||
        text.contains('upgrade') ||
        text.contains('quota') ||
        text.contains('kota') ||
        text.contains('entitlement') ||
        text.contains('ai-') ||
        text.contains('ai_') ||
        text.contains('yetkisiz');
  }
}
