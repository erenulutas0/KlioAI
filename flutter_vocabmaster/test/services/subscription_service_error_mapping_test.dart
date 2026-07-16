import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:vocabmaster/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubscriptionService purchase error mapping', () {
    late SubscriptionService service;

    setUp(() {
      service = SubscriptionService();
    });

    test('maps PG-GEMF-02 raw Play error to restore guidance', () {
      final message = service.debugMapRawPlayError(
        'Google Play Billing failed with PG-GEMF-02',
      );

      expect(message, isNotNull);
      expect(message, contains('PG-GEMF-02'));
      expect(message!.toLowerCase(), contains('restore'));
    });

    test('maps BillingResponse.error raw Play error to retry guidance', () {
      final message = service.debugMapRawPlayError(
        'BillingResponse.error: service unavailable',
      );

      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('try again'));
    });

    test('maps already-owned raw Play error to restore-in-progress guidance',
        () {
      final message = service.debugMapRawPlayError('ITEM_ALREADY_OWNED');

      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('existing store subscription'));
      expect(message.toLowerCase(), contains('restored'));
    });

    test('maps structured IAP PG-GEMF-02 error', () {
      final message = service.debugMapPlayStoreError(
        IAPError(
          source: 'google_play',
          code: 'billing_error',
          message: 'PG-GEMF-02',
        ),
      );

      expect(message, isNotNull);
      expect(message, contains('PG-GEMF-02'));
      expect(message!.toLowerCase(), contains('restore'));
    });

    test('maps verification auth failure to session guidance', () {
      final message = service.debugBuildVerificationErrorMessage(
        401,
        '{"error":"unauthorized"}',
      );

      expect(message.toLowerCase(), contains('session verification failed'));
      expect(message.toLowerCase(), contains('reopen'));
    });

    test('maps backend product-plan mismatch to support guidance', () {
      final message = service.debugBuildVerificationErrorMessage(
        400,
        '{"error":"Unable to map Google product/base plan"}',
      );

      expect(message.toLowerCase(), contains('product plan'));
      expect(message.toLowerCase(), contains('backend mapping'));
    });

    test('maps provider unavailable to retry guidance', () {
      final message = service.debugBuildVerificationErrorMessage(
        503,
        '{"code":"PROVIDER_UNAVAILABLE"}',
      );

      expect(message.toLowerCase(), contains('verification service'));
      expect(message.toLowerCase(), contains('try again'));
    });
  });
}
