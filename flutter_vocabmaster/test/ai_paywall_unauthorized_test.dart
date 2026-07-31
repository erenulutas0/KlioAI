import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/services/ai_paywall_handler.dart';
import 'package:vocabmaster/services/api_service.dart';

/// A 401 has to be sorted into "your session ended" or "you need to pay", and getting it
/// wrong in the paying direction is the expensive mistake: a subscriber whose token expired
/// was shown the subscription page instead of the login screen.
///
/// Spring's entry point answers an expired JWT with {"error":"Unauthorized"} and nothing
/// else, which the old classifier matched with `text.trim() == 'unauthorized'`. It also
/// matched `text.contains('ai')` — those two letters appear in fail, email, available,
/// again, domain, maintenance.

ApiUnauthorizedException _error(String message, {String? reason}) =>
    ApiUnauthorizedException(message: message, reason: reason, statusCode: 401);

void main() {
  group('a 401 that is really an ended session', () {
    test('the bare body Spring sends for an expired JWT is not a paywall', () {
      expect(
        AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(
          _error('Unauthorized'),
        ),
        isFalse,
      );
    });

    test('the same body with the reason the backend now sends is not a paywall', () {
      expect(
        AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(
          _error('Unauthorized', reason: 'session-expired'),
        ),
        isFalse,
      );
    });

    test('an expired-token message is not a paywall', () {
      expect(
        AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(
          _error('JWT expired'),
        ),
        isFalse,
      );
    });

    test('ordinary words containing the letters a-i are not a paywall', () {
      for (final message in [
        'request failed',
        'email not verified',
        'service unavailable',
        'please try again',
        'domain mismatch',
        'server maintenance',
      ]) {
        expect(
          AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(_error(message)),
          isFalse,
          reason: '"$message" must not be read as a billing refusal',
        );
      }
    });
  });

  group('a 401 that really is a billing refusal', () {
    test('an explicit subscription reason opens the paywall', () {
      for (final reason in [
        'subscription-required',
        'premium-required',
        'ai-quota-exceeded',
        'entitlement-missing',
      ]) {
        expect(
          AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(
            _error('Unauthorized', reason: reason),
          ),
          isTrue,
          reason: '"$reason" is a billing signal',
        );
      }
    });

    test('a Turkish subscription message opens the paywall', () {
      expect(
        AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(
          _error('Bu ozellik icin abonelik gerekli'),
        ),
        isTrue,
      );
    });

    test('an exhausted quota opens the paywall', () {
      expect(
        AiPaywallHandler.shouldOpenSubscriptionForUnauthorized(
          _error('Gunluk kota doldu'),
        ),
        isTrue,
      );
    });
  });
}
