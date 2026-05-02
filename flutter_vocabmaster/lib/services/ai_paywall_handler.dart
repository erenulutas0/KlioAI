import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../screens/subscription_page.dart';
import '../screens/login_page.dart';
import 'ai_error_message_formatter.dart';
import 'api_service.dart';
import 'auth_service.dart';

class AiPaywallHandler {
  static Future<void> openSubscription(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SubscriptionPage()),
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

  static bool _shouldOpenSubscriptionForUnauthorized(
    ApiUnauthorizedException error,
  ) {
    final text = '${error.reason ?? ''} ${error.message}'.toLowerCase();
    if (text.contains('missing-auth') ||
        text.contains('oturum') ||
        text.contains('session') ||
        text.contains('token') ||
        text.contains('giris') ||
        text.contains('login')) {
      return false;
    }

    return text.contains('abon') ||
        text.contains('subscription') ||
        text.contains('premium') ||
        text.contains('upgrade') ||
        text.contains('ai') ||
        text.contains('yetkisiz') ||
        text.trim() == 'unauthorized' ||
        text.trim().endsWith(' unauthorized');
  }
}
